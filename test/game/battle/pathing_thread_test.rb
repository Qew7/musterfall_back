require "test_helper"

class SimBattlePathingThreadTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  Pathing = Sim::Battle::Pathing
  Thread = Sim::Battle::Pathing::Thread

  test "open LOS is a single thread segment" do
    actor = BattleScenarios.combatant(x: 6.0, y: 12.0, facing: 0.0)
    goal = { x: 24.0, y: 12.0 }
    kernels = Pathing.obstacle_kernels([ actor ])
    thread = Thread.pull(mover: actor, goal: goal, obstacles: [ actor ], contact_id: nil, kernels: kernels)

    assert thread[:complete]
    assert_equal 2, thread[:points].length
    assert_in_delta 6.0, thread[:points].first[:x], 0.05
    assert_in_delta 24.0, thread[:points].last[:x], 0.05
  end

  test "a blocker on the line pulls the thread around the OBB with clearance" do
    actor = BattleScenarios.combatant(x: 6.0, y: 12.0, facing: 0.0, base_width: 2.0, base_depth: 2.0)
    house = BattleScenarios.terrain(id: "house", x: 16.0, y: 12.0, width: 3.0, depth: 3.0)
    goal = { x: 28.0, y: 12.0 }
    obstacles = Pathing.merge_obstacles([ actor ], [ house ])
    kernels = Pathing.obstacle_kernels(obstacles)
    thread = Thread.pull(mover: actor, goal: goal, obstacles: obstacles, contact_id: nil, kernels: kernels)
    house_obs = BF.feature_as_obstacle(house)

    assert thread[:complete]
    assert_operator thread[:points].length, :>=, 3
    thread[:points].each do |point|
      pose = actor.merge(x: point[:x], y: point[:y])
      refute BF.rectangles_overlap?(pose, house_obs), "thread vertex #{point.inspect} overlaps the house"
    end
    assert thread[:points].any? { |point| (point[:y] - actor[:y]).abs > 0.4 }
  end

  test "a wide tray does not squeeze through a point-sized gap" do
    actor = BattleScenarios.combatant(x: 6.0, y: 12.0, facing: 0.0, base_width: 5.0, base_depth: 2.0)
    upper = BattleScenarios.combatant(entity_id: "u", x: 14.0, y: 15.2, facing: 0.0, base_width: 4.0, base_depth: 2.0)
    lower = BattleScenarios.combatant(entity_id: "l", x: 14.0, y: 8.8, facing: 0.0, base_width: 4.0, base_depth: 2.0)
    goal = { x: 28.0, y: 12.0 }
    obstacles = [ actor, upper, lower ]
    kernels = Pathing.obstacle_kernels(obstacles)
    thread = Thread.pull(mover: actor, goal: goal, obstacles: obstacles, contact_id: nil, kernels: kernels)

    refute Thread.segment_clear?(actor, { x: 6.0, y: 12.0 }, { x: 28.0, y: 12.0 }, kernels, nil)
    thread[:points].each do |point|
      pose = actor.merge(x: point[:x], y: point[:y])
      refute BF.rectangles_overlap?(pose, upper)
      refute BF.rectangles_overlap?(pose, lower)
    end
  end

  test "follow wraps an ally with wheel or turn then advance" do
    actor = BattleScenarios.combatant(x: 8.0, y: 12.0, facing: 0.0, movement: 5.0, base_width: 3.0, base_depth: 3.0)
    ally = BattleScenarios.combatant(entity_id: "boyz", x: 14.0, y: 12.0, facing: 0.0, base_width: 4.0, base_depth: 4.0)
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
    assert plan[:avoided]
    kinds = Array(plan[:steps]).map { |step| step[:kind] }
    assert (kinds & %w[wheel turn]).any?
    landed = BF.merge_footprint(actor, plan[:pose])
    refute BF.rectangles_overlap?(landed, ally)
    assert_operator BF.distance_between(actor, plan[:pose]), :>, 0.2
  end

  test "boxed-by-allies thread does not claim a path through the box" do
    actor = BattleScenarios.combatant(x: 6.0, y: 12.0, facing: 0.0)
    front = BattleScenarios.combatant(entity_id: "front", x: 10.0, y: 12.0, base_width: 4.0, base_depth: 4.0)
    upper = BattleScenarios.combatant(entity_id: "upper", x: 6.0, y: 8.5, base_width: 4.0, base_depth: 2.0)
    lower = BattleScenarios.combatant(entity_id: "lower", x: 6.0, y: 15.5, base_width: 4.0, base_depth: 2.0)
    goal = { x: 30.0, y: 12.0 }
    obstacles = [ actor, front, upper, lower ]
    kernels = Pathing.obstacle_kernels(obstacles)
    thread = Thread.pull(mover: actor, goal: goal, obstacles: obstacles, contact_id: nil, kernels: kernels)

    thread[:points].each do |point|
      pose = actor.merge(x: point[:x], y: point[:y])
      refute BF.rectangles_overlap?(pose, front)
      refute BF.rectangles_overlap?(pose, upper)
      refute BF.rectangles_overlap?(pose, lower)
    end
    through = thread[:points].each_cons(2).any? do |a, b|
      (a[:y] - 12.0).abs < 0.6 && (b[:y] - 12.0).abs < 0.6 &&
        a[:x] < 10.0 && b[:x] > 10.0
    end
    refute through, "thread went through the boxed front instead of around"
  end

  test "flank contact_slot anchors the thread off the defender center" do
    actor = BattleScenarios.combatant(x: 10.0, y: 6.0, facing: 90.0, base_width: 1.0, base_depth: 1.0)
    enemy = BattleScenarios.enemy(x: 16.0, y: 12.0, facing: 180.0, base_width: 4.0, base_depth: 3.0)
    anchor = Thread.anchor(
      origin: actor,
      goal_point: enemy,
      goal_unit: enemy,
      contact_id: enemy[:entity_id],
      contact_slot: "flank",
      approach_mode: :orbit_flank
    )

    assert_operator (anchor[:y] - enemy[:y]).abs, :>, 0.5
    assert_operator BF.distance_between(anchor, enemy), :>, 1.0
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
    refute_equal "terrain-1", plan[:blocker] && plan[:blocker][:entity_id]
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

  test "thread first hop around a friend is not the jammed face midpoint" do
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
    thread = Thread.pull(mover: actor, goal: enemy, world: world, contact_id: enemy[:entity_id])
    first = thread[:points][1]
    heading = BF.heading_to(thread[:points][0], first)
    along = BF.distance_between(actor, first)
    into_friend = BF.shortest_facing_delta(actor[:facing], heading).abs < 15.0 && along < 1.0

    assert_operator thread[:points].length, :>=, 3
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
    leftover = 3.0 - plan[:cost_spent].to_f
    assert leftover <= 0.5 || plan[:avoided],
           "spent #{plan[:cost_spent]} leftover #{leftover} avoided=#{plan[:avoided]} blocker=#{plan[:blocker].inspect}"
  end

  test "support block wraps a friend toward the enemy instead of turning to the map edge" do
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
end
