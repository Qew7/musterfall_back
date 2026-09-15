require "sim_test_helper"

class SimBattlePathingRouteTest < SimTestCase
  BF = Sim::Geometry::Battlefield
  Pathing = Sim::Battle::Pathing
  Route = Sim::Battle::Pathing::Route

  test "open LOS is a single route segment" do
    actor = BattleScenarios.combatant(x: 6.0, y: 12.0, facing: 0.0)
    goal = { x: 24.0, y: 12.0 }
    kernels = Pathing.obstacle_kernels([ actor ])
    route = Route.pull(mover: actor, goal: goal, obstacles: [ actor ], contact_id: nil, kernels: kernels)

    assert route[:complete]
    assert_equal 2, route[:points].length
    assert_in_delta 6.0, route[:points].first[:x], 0.05
    assert_in_delta 24.0, route[:points].last[:x], 0.05
  end

  test "a 5x4 tray routes around a lakeshore without snagging corners" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-16", x: 32.31, y: 11.19, facing: 173.5,
      base_width: 5.0, base_depth: 4.0, movement: 3.0
    )
    enemy = BattleScenarios.enemy(entity_id: "unit-32", x: 1.0, y: 10.0, facing: 0.0)
    lake = BattleScenarios.terrain(
      id: "terrain-1", type: "lake", x: 25.922, y: 7.12, width: 3.877, depth: 2.36, impassable: true
    )
    world = Pathing::Obstacles.merge([ actor, enemy ], [ lake ])
    lake_obs = BF.feature_as_obstacle(lake)
    route = Route.pull(mover: actor, goal: enemy, world: world, contact_id: enemy[:entity_id])

    assert_operator route[:points].length, :>=, 3
    route[:points].each_cons(2) do |_from, vertex|
      heading = BF.heading_to(route[:points].first, vertex)
      pose = actor.merge(x: vertex[:x], y: vertex[:y], facing: heading)
      refute BF.rectangles_overlap?(pose, lake_obs), "route vertex #{vertex.inspect} overlaps the lake"
    end

    plan = Pathing.plan_approach(
      origin: actor, goal_point: enemy, budget: 3.0,
      obstacles: world, contact_id: enemy[:entity_id], goal_unit: enemy, terrain: [ lake ]
    )
    leftover = 3.0 - plan[:cost_spent].to_f
    landed = BF.merge_footprint(actor, plan[:pose])
    refute BF.rectangles_overlap?(landed, lake_obs)
    assert leftover <= 0.6, "leftover #{leftover} unused at the lake"
    assert_operator BF.distance_between(actor, plan[:pose]), :>, 0.5
    route_y = route[:points][1][:y]
    assert_operator route_y, :>, 8.3, "route vertex y=#{route_y} is not north of the lake"
  end

  test "a blocker on the line pulls the route around the OBB with clearance" do
    actor = BattleScenarios.combatant(x: 6.0, y: 12.0, facing: 0.0, base_width: 2.0, base_depth: 2.0)
    house = BattleScenarios.terrain(id: "house", x: 16.0, y: 12.0, width: 3.0, depth: 3.0)
    goal = { x: 28.0, y: 12.0 }
    obstacles = Pathing.merge_obstacles([ actor ], [ house ])
    kernels = Pathing.obstacle_kernels(obstacles)
    route = Route.pull(mover: actor, goal: goal, obstacles: obstacles, contact_id: nil, kernels: kernels)
    house_obs = BF.feature_as_obstacle(house)

    assert route[:complete]
    assert_operator route[:points].length, :>=, 3
    route[:points].each do |point|
      pose = actor.merge(x: point[:x], y: point[:y])
      refute BF.rectangles_overlap?(pose, house_obs), "route vertex #{point.inspect} overlaps the house"
    end
    assert route[:points].any? { |point| (point[:y] - actor[:y]).abs > 0.4 }
  end

  test "a wide tray does not squeeze through a point-sized gap" do
    actor = BattleScenarios.combatant(x: 6.0, y: 12.0, facing: 0.0, base_width: 5.0, base_depth: 2.0)
    upper = BattleScenarios.combatant(entity_id: "u", x: 14.0, y: 15.2, facing: 0.0, base_width: 4.0, base_depth: 2.0)
    lower = BattleScenarios.combatant(entity_id: "l", x: 14.0, y: 8.8, facing: 0.0, base_width: 4.0, base_depth: 2.0)
    goal = { x: 28.0, y: 12.0 }
    obstacles = [ actor, upper, lower ]
    kernels = Pathing.obstacle_kernels(obstacles)
    route = Route.pull(mover: actor, goal: goal, obstacles: obstacles, contact_id: nil, kernels: kernels)

    refute Route.segment_clear?(actor, { x: 6.0, y: 12.0 }, { x: 28.0, y: 12.0 }, kernels, nil)
    route[:points].each do |point|
      pose = actor.merge(x: point[:x], y: point[:y])
      refute BF.rectangles_overlap?(pose, upper)
      refute BF.rectangles_overlap?(pose, lower)
    end
  end

  test "route uses wheel or turn then advance around an ally" do
    actor = BattleScenarios.combatant(x: 8.0, y: 12.0, facing: 0.0, movement: 5.0, base_width: 3.0, base_depth: 3.0)
    ally = BattleScenarios.combatant(entity_id: "brutes", x: 14.0, y: 12.0, facing: 0.0, base_width: 4.0, base_depth: 4.0)
    enemy = BattleScenarios.enemy(x: 26.0, y: 12.0, facing: 180.0)
    plan = Pathing.plan_approach(
      origin: actor,
      goal_point: enemy,
      budget: 5.0,
      obstacles: [ actor, ally, enemy ],
      contact_id: enemy[:entity_id],
      goal_unit: enemy
    )

    assert plan[:pose]
    refute plan[:blocked_by_ally]
    kinds = Array(plan[:steps]).map { |step| step[:kind] }
    assert (kinds & %w[wheel turn]).any?
    landed = BF.merge_footprint(actor, plan[:pose])
    refute BF.rectangles_overlap?(landed, ally)
    assert_operator BF.distance_between(actor, plan[:pose]), :>, 0.2
  end

  test "boxed-by-allies route does not claim a path through the box" do
    actor = BattleScenarios.combatant(x: 6.0, y: 12.0, facing: 0.0)
    front = BattleScenarios.combatant(entity_id: "front", x: 10.0, y: 12.0, base_width: 4.0, base_depth: 4.0)
    upper = BattleScenarios.combatant(entity_id: "upper", x: 6.0, y: 8.5, base_width: 4.0, base_depth: 2.0)
    lower = BattleScenarios.combatant(entity_id: "lower", x: 6.0, y: 15.5, base_width: 4.0, base_depth: 2.0)
    goal = { x: 30.0, y: 12.0 }
    obstacles = [ actor, front, upper, lower ]
    kernels = Pathing.obstacle_kernels(obstacles)
    route = Route.pull(mover: actor, goal: goal, obstacles: obstacles, contact_id: nil, kernels: kernels)

    route[:points].each do |point|
      pose = actor.merge(x: point[:x], y: point[:y])
      refute BF.rectangles_overlap?(pose, front)
      refute BF.rectangles_overlap?(pose, upper)
      refute BF.rectangles_overlap?(pose, lower)
    end
    through = route[:points].each_cons(2).any? do |a, b|
      (a[:y] - 12.0).abs < 0.6 && (b[:y] - 12.0).abs < 0.6 &&
        a[:x] < 10.0 && b[:x] > 10.0
    end
    refute through, "route went through the boxed front instead of around"
  end

  test "route anchor keeps a precomputed goal instead of re-deriving orbit slots" do
    actor = BattleScenarios.combatant(x: 10.0, y: 6.0, facing: 90.0, base_width: 1.0, base_depth: 1.0)
    enemy = BattleScenarios.enemy(x: 16.0, y: 12.0, facing: 180.0, base_width: 4.0, base_depth: 3.0)
    given = { x: 20.0, y: 8.0 }
    anchor = Route.anchor(
      origin: actor,
      goal_point: given,
      goal_unit: enemy,
      contact_id: enemy[:entity_id],
      contact_slot: "flank",
      approach_mode: :orbit_flank
    )

    assert_in_delta 20.0, anchor[:x], 0.001
    assert_in_delta 8.0, anchor[:y], 0.001
  end

  test "boxed infantry stops short of a lake instead of marching into it" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-34", x: 8.0, y: 12.0, facing: 0.0,
      base_width: 4.0, base_depth: 4.0, movement: 4.0
    )
    north = BattleScenarios.combatant(entity_id: "unit-35", x: 8.0, y: 20.0, base_width: 4.0, base_depth: 4.0)
    south = BattleScenarios.combatant(entity_id: "unit-36", x: 4.0, y: 4.0, base_width: 4.0, base_depth: 4.0)
    enemy = BattleScenarios.enemy(entity_id: "unit-9", x: 31.0, y: 11.0, facing: 180.0, base_width: 3.0, base_depth: 4.0)
    lake = BattleScenarios.terrain(
      id: "terrain-1", type: "lake", x: 16.013, y: 11.581, width: 5.13, depth: 3.563, impassable: true
    )
    world = Pathing::Obstacles.merge([ actor, north, south, enemy ], [ lake ])
    lake_obs = BF.feature_as_obstacle(lake)
    plan = Pathing.plan_approach(
      origin: actor, goal_point: enemy, budget: 4.0,
      obstacles: world, contact_id: enemy[:entity_id], goal_unit: enemy,
      terrain: [ lake ], march_allowed: true
    )

    assert plan[:pose]
    landed = BF.merge_footprint(actor, plan[:pose])
    refute BF.rectangles_overlap?(landed, lake_obs)
    refute_operator landed[:x], :<, actor[:x] - 0.6
  end

  test "a wide tray behind a friend turns when the wheel cannot clear this frontage" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-11", x: 35.0, y: 19.0, facing: 180.0,
      base_width: 4.0, base_depth: 4.0, files: 2, ranks: 2, movement: 3.0
    )
    friend = BattleScenarios.combatant(
      entity_id: "hero-2", x: 31.0, y: 19.0, facing: 180.0,
      base_width: 1.0, base_depth: 1.0
    )
    enemy = BattleScenarios.enemy(entity_id: "unit-36", x: 8.0, y: 16.0, facing: 0.0)
    world = Pathing::Obstacles.merge([ actor, friend, enemy ], [])
    plan = Pathing.plan_approach(
      origin: actor, goal_point: enemy, budget: 3.0,
      obstacles: world, contact_id: enemy[:entity_id], goal_unit: enemy
    )

    assert plan[:pose]
    landed = BF.merge_footprint(actor, plan[:pose])
    refute BF.rectangles_overlap?(landed, friend)
    kinds = Array(plan[:steps]).map { |step| step[:kind] }
    assert_includes kinds, "turn"
    leftover = 3.0 - plan[:cost_spent].to_f
    assert leftover <= 0.6, "leftover #{leftover} unused in front of #{friend[:entity_id]}"
    assert_operator BF.distance_between(actor, plan[:pose]), :>, 0.5
  end

  test "route first hop around a friend is not the jammed face midpoint" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-11", x: 35.0, y: 19.0, facing: 180.0,
      base_width: 4.0, base_depth: 4.0, files: 2, ranks: 2, movement: 3.0
    )
    friend = BattleScenarios.combatant(
      entity_id: "hero-2", x: 31.0, y: 19.0, facing: 180.0,
      base_width: 1.0, base_depth: 1.0
    )
    enemy = BattleScenarios.enemy(entity_id: "unit-36", x: 8.0, y: 16.0, facing: 0.0)
    world = Pathing::Obstacles.merge([ actor, friend, enemy ], [])
    route = Route.pull(mover: actor, goal: enemy, world: world, contact_id: enemy[:entity_id])
    first = route[:points][1]
    heading = BF.heading_to(route[:points][0], first)
    along = BF.distance_between(actor, first)
    into_friend = BF.shortest_facing_delta(actor[:facing], heading).abs < 15.0 && along < 1.0

    assert_operator route[:points].length, :>=, 3
    refute into_friend, "first hop #{first.inspect} is the jammed face midpoint"
  end

  test "a house on the line of sight does not clip an open first stride" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-10", x: 31.0, y: 3.0, facing: 180.0,
      base_width: 4.0, base_depth: 4.0, movement: 3.0
    )
    enemy = BattleScenarios.enemy(entity_id: "unit-37", x: 4.0, y: 4.0, facing: 0.0)
    house = BattleScenarios.terrain(
      id: "terrain-5", type: "house", x: 13.62, y: 2.855, width: 3.342, depth: 3.499
    )
    world = Pathing::Obstacles.merge([ actor, enemy ], [ house ])
    house_obs = BF.feature_as_obstacle(house)
    plan = Pathing.plan_approach(
      origin: actor, goal_point: enemy, budget: 3.0,
      obstacles: world, contact_id: enemy[:entity_id], goal_unit: enemy, terrain: [ house ]
    )

    assert plan[:pose]
    landed = BF.merge_footprint(actor, plan[:pose])
    refute BF.rectangles_overlap?(landed, house_obs)
    refute_equal "terrain-5", plan[:blocker] && plan[:blocker][:entity_id]
    assert_operator BF.distance_between(actor, plan[:pose]), :>, 0.2
  end

  test "almost-contact approach does not turn into the map edge" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-10", x: 23.07, y: 2.1, facing: 149.3,
      base_width: 4.0, base_depth: 4.0, files: 2, ranks: 2, movement: 3.0
    )
    enemy = BattleScenarios.enemy(
      entity_id: "unit-35", x: 17.87, y: 3.7, facing: 15.9,
      base_width: 4.0, base_depth: 4.0, files: 4, ranks: 4
    )
    world = Pathing::Obstacles.merge([ actor, enemy ], [])
    gap = BF.distance_between_units(actor, enemy)
    assert_operator gap, :<, 1.0

    goal = Sim::Battle::Rules::Ground::Movement.approach_goal_point(
      actor, enemy, contact_slot: "front", approach_mode: :direct
    )
    plan = Pathing.plan_approach(
      origin: actor, goal_point: goal, budget: 3.0,
      obstacles: world, contact_id: enemy[:entity_id], goal_unit: enemy
    )

    refute_equal :turn, plan[:maneuver], "turned to #{plan.dig(:pose, :facing)} instead of closing #{gap.round(2)}\""
    landed = BF.merge_footprint(actor, plan[:pose])
    assert_operator BF.distance_between_units(landed, enemy), :<=, gap
    assert_in_delta actor[:facing], landed[:facing], 20.0
  end

  test "support block routes around a friend toward the enemy instead of turning to the map edge" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-36", x: 4.0, y: 4.0, facing: 0.0,
      base_width: 4.0, base_depth: 4.0, movement: 4.0
    )
    mage = BattleScenarios.combatant(entity_id: "hero-1", x: 8.0, y: 4.0, base_width: 1.0, base_depth: 1.0)
    enemy = BattleScenarios.enemy(entity_id: "unit-10", x: 31.0, y: 3.0, facing: 180.0, base_width: 2.0, base_depth: 2.0)
    world = Pathing::Obstacles.merge([ actor, mage, enemy ], [])
    plan = Pathing.plan_approach(
      origin: actor, goal_point: enemy, budget: 4.0,
      obstacles: world, contact_id: enemy[:entity_id], goal_unit: enemy
    )

    assert plan[:pose]
    landed = BF.merge_footprint(actor, plan[:pose])
    refute BF.rectangles_overlap?(landed, mage)
    leftover = 4.0 - plan[:cost_spent].to_f
    assert leftover <= 1.0, "leftover #{leftover} unused in front of the mage"
    assert_operator landed[:y], :>, actor[:y] + 0.3
    refute_in_delta 270.0, landed[:facing], 15.0
    assert_operator landed[:x], :>=, actor[:x] - 0.05
  end

  test "a 4x4 tray routes around a house without crossing the north edge" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-19", x: 16.96, y: 19.87, facing: 358.9,
      base_width: 4.0, base_depth: 4.0, files: 4, ranks: 4, movement: 3.0
    )
    enemy = BattleScenarios.enemy(
      entity_id: "hero-2", x: 31.0, y: 19.0, facing: 180.0,
      base_width: 1.0, base_depth: 1.0
    )
    house = BattleScenarios.terrain(
      id: "terrain-3", type: "house", x: 25.76, y: 17.65, width: 3.32, depth: 2.1
    )
    world = Pathing::Obstacles.merge([ actor, enemy ], [ house ])
    route = Route.pull(mover: actor, goal: enemy, world: world, contact_id: enemy[:entity_id])
    house_obs = BF.feature_as_obstacle(house)

    route_point = route[:points][1]
    assert route_point, "route has no intermediate point"
    route[:points].each do |point|
      pose = actor.merge(x: point[:x], y: point[:y])
      assert BF.tray_on_battlefield?(pose), "route vertex #{point.inspect} leaves the battlefield"
      refute BF.rectangles_overlap?(pose, house_obs), "route vertex #{point.inspect} overlaps the house"
    end

    plan = Pathing.plan_approach(
      origin: actor, goal_point: enemy, budget: 3.0,
      obstacles: world, contact_id: enemy[:entity_id], goal_unit: enemy, terrain: [ house ]
    )
    landed = BF.merge_footprint(actor, plan[:pose])
    refute BF.rectangles_overlap?(landed, house_obs)
    kinds = Array(plan[:steps]).map { |step| step[:kind] }
    assert_includes kinds, "wheel"
    leftover = 3.0 - plan[:cost_spent].to_f
    assert leftover <= 0.6, "leftover #{leftover} unused against the house corner"
    assert BF.tray_on_battlefield?(landed)
  end

  test "battle 725 goblin archers do not route above the battlefield lake" do
    archers = BattleScenarios.combatant(
      entity_id: "unit-5", x: 31, y: 3, facing: 180,
      base_width: 5, base_depth: 3, files: 5, ranks: 3, movement: 4
    )
    target = BattleScenarios.enemy(
      entity_id: "target", x: 8, y: 3, facing: 0,
      base_width: 4, base_depth: 3
    )
    lake = BattleScenarios.terrain(
      id: "terrain-6", type: "lake", x: 21.721, y: 3.072,
      width: 5.327, depth: 3.76
    )
    world = Pathing::Obstacles.merge([ archers, target ], [ lake ])
    route = Route.pull(
      mover: archers,
      goal: target,
      world: world,
      contact_id: target[:entity_id]
    )

    route[:points].each do |point|
      assert BF.tray_on_battlefield?(archers.merge(point)), point.inspect
    end
    plan = Pathing.plan_approach(
      origin: archers,
      goal_point: target,
      budget: 8,
      obstacles: world,
      contact_id: target[:entity_id],
      goal_unit: target,
      terrain: [ lake ],
      march_allowed: true
    )
    assert BF.tray_on_battlefield?(BF.merge_footprint(archers, plan[:pose]))
  end
end
