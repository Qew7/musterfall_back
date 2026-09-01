require "test_helper"

class SimBattlePathingContractTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  Pathing = Sim::Battle::Pathing
  Thread = Sim::Battle::Pathing::Thread

  test "open ground is a clear thread segment" do
    actor = BattleScenarios.combatant(x: 4.0, y: 12.0, facing: 0.0)
    target = { x: 30.0, y: 12.0 }
    kernels = Pathing.obstacle_kernels([ actor ])

    assert Thread.segment_clear?(actor, actor, target, kernels, nil)
  end

  test "thread segment sees a thin wall on a long line" do
    actor = BattleScenarios.combatant(x: 2.0, y: 12.0, facing: 0.0)
    target = { x: 36.0, y: 12.0 }
    wall = BattleScenarios.terrain(id: "wall", x: 20.0, y: 12.0, width: 1.0, depth: 4.0)
    obstacles = Pathing.merge_obstacles([ actor ], [ wall ])
    kernels = Pathing.obstacle_kernels(obstacles)

    refute Thread.segment_clear?(actor, actor, target, kernels, nil)
  end

  test "taut pull removes interior waypoints that stay clear" do
    actor = BattleScenarios.combatant(x: 4.0, y: 12.0, facing: 0.0)
    path = [
      { x: 4.0, y: 12.0 },
      { x: 8.0, y: 12.0 },
      { x: 12.0, y: 12.0 },
      { x: 16.0, y: 12.0 }
    ]
    kernels = Pathing.obstacle_kernels([ actor ])
    pulled = Thread.taut(actor, path, kernels, nil)

    assert_equal 2, pulled.length
    assert_in_delta 4.0, pulled.first[:x], 0.001
    assert_in_delta 16.0, pulled.last[:x], 0.001
  end

  test "thread wraps a house instead of going through it" do
    actor = BattleScenarios.combatant(x: 6.0, y: 8.0, facing: 0.0)
    target = BattleScenarios.enemy(x: 31.0, y: 8.0, facing: 180.0)
    house = BattleScenarios.terrain(id: "house", x: 18.0, y: 8.0, width: 3.0, depth: 3.0)
    obstacles = Pathing.merge_obstacles([ actor, target ], [ house ])
    house_obs = BF.feature_as_obstacle(house)
    kernels = Pathing.obstacle_kernels(obstacles)
    thread = Thread.pull(
      mover: actor, goal: target, obstacles: obstacles,
      contact_id: target[:entity_id], kernels: kernels
    )

    assert_operator thread[:points].length, :>=, 2
    thread[:points].each do |point|
      pose = actor.merge(x: point[:x], y: point[:y])
      refute BF.rectangles_overlap?(pose, house_obs), "thread vertex #{point.inspect} hits the house"
    end
    assert thread[:points].any? { |point| (point[:y] - actor[:y]).abs >= 0.4 },
           "expected the house thread to leave the east-west line through the house"
  end

  test "wide block facing a lake wheels onto a corridor instead of holding" do
    actor = BattleScenarios.combatant(
      x: 8.0, y: 12.0, facing: 0.0, movement: 3.0, base_width: 5.0, base_depth: 2.0
    )
    target = BattleScenarios.enemy(x: 31.0, y: 12.0, facing: 180.0, base_width: 4.0, base_depth: 3.0)
    lake = BattleScenarios.terrain(
      id: "lake", type: "lake", x: 14.7, y: 10.2, width: 3.072, depth: 3.096, impassable: true
    )
    obstacles = Pathing.merge_obstacles([ actor, target ], [ lake ])
    lake_obs = BF.feature_as_obstacle(lake)
    plan = Pathing.plan_approach(
      origin: actor, goal_point: target, budget: 6.0,
      obstacles: obstacles, contact_id: target[:entity_id], goal_unit: target, terrain: [ lake ]
    )
    assert plan[:pose]
    landed = actor.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
    refute BF.rectangles_overlap?(landed, lake_obs)
    assert Pathing.meaningful_progress?(actor, plan[:pose])
    turned = BF.shortest_facing_delta(actor[:facing], landed[:facing]).abs > 15.0
    stepped_aside = (landed[:y] - actor[:y]).abs > 0.2
    assert turned || stepped_aside, "expected a wheel onto the shore corridor, got #{landed.inspect}"
  end

  test "wheel samples spend outer-corner MV, not center travel" do
    actor = BattleScenarios.combatant(x: 10.0, y: 12.0, facing: 0.0, base_width: 5.0, base_depth: 2.0)
    heading = 90.0
    wheel = Sim::Geometry::Battlefield.apply_wheel(actor, heading, 8.0)
    desired = actor.merge(x: wheel[:x], y: wheel[:y], facing: wheel[:facing])
    plan = Pathing.furthest_clear_pose(
      actor, wheel, desired, [ actor ],
      contact_id: nil, budget: 4.0
    )

    assert plan[:pose]
    spent = plan[:cost_spent].to_f
    assert_operator spent, :<=, 4.0 + 0.3
    assert_operator spent, :>, 1.0
  end

  test "wheel-then-advance does not crab-walk: translation follows facing" do
    actor = BattleScenarios.combatant(x: 8.0, y: 12.0, facing: 0.0, movement: 6.0)
    target = BattleScenarios.enemy(x: 28.0, y: 12.0, facing: 180.0)
    plan = Pathing.plan_approach(
      origin: actor,
      goal_point: target,
      budget: 6.0,
      obstacles: [ actor, target ],
      contact_id: target[:entity_id],
      goal_unit: target
    )

    assert plan[:pose]
    BattleInvariants.verify_pathing_plan!(
      actor, plan, obstacles: [ target ], budget: 6.0, contact_id: target[:entity_id]
    )
    landed = actor.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
    dx = landed[:x] - actor[:x]
    dy = landed[:y] - actor[:y]
    if Math.hypot(dx, dy) > 0.4
      forward = BF.facing_vector(landed[:facing])
      along = (dx * forward[:x]) + (dy * forward[:y])
      assert_operator along, :>, -0.15, "remaining-moves translation is along facing, not a crab-walk"
    end
  end

  test "allies wrap a frontal blocker instead of holding the column" do
    origin = BattleScenarios.combatant(
      entity_id: "boars", x: 8.0, y: 12.0, facing: 0.0, base_width: 3.0, base_depth: 3.0, side_index: 0
    )
    ally = BattleScenarios.combatant(
      entity_id: "brutes", x: 14.0, y: 12.0, facing: 0.0, base_width: 4.0, base_depth: 4.0, side_index: 0
    )
    enemy = BattleScenarios.enemy(x: 22.0, y: 12.0, facing: 180.0, base_width: 2.0, base_depth: 2.0)
    plan = Pathing.plan_approach(
      origin: origin,
      goal_point: enemy,
      budget: 5.0,
      obstacles: [ origin, ally, enemy ],
      contact_id: enemy[:entity_id],
      goal_unit: enemy
    )

    refute plan[:blocked_by_ally]
    assert plan[:pose]
    traveled = BF.distance_between(origin, plan[:pose])
    assert_operator traveled, :>, 0.2
    landed = origin.merge(plan[:pose])
    refute BF.rectangles_overlap?(landed, ally)
  end

  test "approach around a lake never overlaps it" do
    actor = BattleScenarios.combatant(
      x: 8.0, y: 20.0, facing: 0.0, movement: 4.0, base_width: 5.0, base_depth: 2.0
    )
    target = BattleScenarios.enemy(x: 35.0, y: 19.0, facing: 180.0, base_width: 4.0, base_depth: 4.0)
    lake = BattleScenarios.terrain(
      id: "lake", type: "lake", x: 14.55, y: 18.38, width: 5.382, depth: 3.897, impassable: true
    )
    obstacles = Pathing.merge_obstacles([ actor, target ], [ lake ])
    lake_obs = BF.feature_as_obstacle(lake)
    plan = Pathing.plan_approach(
      origin: actor,
      goal_point: target,
      budget: 6.0,
      obstacles: obstacles,
      contact_id: target[:entity_id],
      goal_unit: target,
      terrain: [ lake ]
    )

    assert plan[:pose]
    landed = actor.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
    refute BF.rectangles_overlap?(landed, lake_obs)
    BattleInvariants.verify_pathing_plan!(
      actor, plan, obstacles: obstacles, budget: 6.0, contact_id: target[:entity_id]
    )
  end

  test "ghouls south of lake-2 do not reverse east" do
    actor = BattleScenarios.combatant(
      x: 31.0, y: 19.0, facing: 180.0, movement: 4.0, base_width: 4.0, base_depth: 3.0
    )
    target = BattleScenarios.enemy(x: 8.0, y: 20.0, facing: 0.0, base_width: 4.0, base_depth: 3.0)
    lakes = PathingAudit.matchup_lakes
    obstacles = Pathing.merge_obstacles([ actor, target ], lakes)
    plan = Pathing.plan_approach(
      origin: actor, goal_point: target, budget: 8.0,
      obstacles: obstacles, contact_id: target[:entity_id], goal_unit: target, terrain: lakes
    )

    assert plan[:pose]
    landed = actor.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
    lakes.each do |lake|
      refute BF.rectangles_overlap?(landed, BF.feature_as_obstacle(lake))
    end
    refute_operator landed[:x], :>, actor[:x] + 0.2
    assert Pathing.meaningful_progress?(actor, plan[:pose])
  end

  test "ghouls south of the lakes assault the corridor goblins instead of cutting into lake-1" do
    actor = BattleScenarios.combatant(
      entity_id: "ghouls", x: 23.09, y: 19.28, facing: 177.5,
      base_width: 4.0, base_depth: 3.0, movement: 4.0, melee: 4, side_index: 1
    )
    trolls = BattleScenarios.enemy(
      entity_id: "trolls", x: 8.0, y: 12.0, facing: 0.0, base_width: 4.0, base_depth: 4.0
    )
    goblins = BattleScenarios.enemy(
      entity_id: "goblins", x: 8.0, y: 20.0, facing: 0.0, base_width: 4.0, base_depth: 3.0
    )
    lakes = PathingAudit.matchup_lakes
    obstacles = Pathing.merge_obstacles([ actor, trolls, goblins ], lakes)
    entries = Sim::Battle::Decisions::Movement.plan_melee_entries(
      [ actor ], [ trolls, goblins ], terrain: lakes
    )

    assert entries.first
    target = entries.first[:nearest]
    plan = Pathing.plan_approach(
      origin: actor, goal_point: target, budget: 8.0,
      obstacles: obstacles, contact_id: target[:entity_id], goal_unit: target, terrain: lakes
    )
    assert plan[:pose]
    landed = actor.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
    lakes.each do |lake|
      refute BF.rectangles_overlap?(landed, BF.feature_as_obstacle(lake))
    end
  end

  test "trolls facing the matchup lake with friends behind do not grind into it" do
    actor = BattleScenarios.combatant(
      entity_id: "trolls", x: 8.0, y: 12.0, facing: 0.0,
      base_width: 4.0, base_depth: 4.0, movement: 3.0, side_index: 0
    )
    friend = BattleScenarios.combatant(
      entity_id: "archers", x: 4.0, y: 12.0, facing: 0.0,
      base_width: 4.0, base_depth: 3.0, side_index: 0
    )
    target = BattleScenarios.enemy(x: 31.0, y: 3.0, facing: 180.0, base_width: 2.0, base_depth: 2.0)
    lakes = PathingAudit.matchup_lakes
    obstacles = Pathing.merge_obstacles([ actor, friend, target ], lakes)
    lake_obs = BF.feature_as_obstacle(lakes.first)
    plan = Pathing.plan_approach(
      origin: actor, goal_point: target, budget: 6.0,
      obstacles: obstacles, contact_id: target[:entity_id], goal_unit: target, terrain: lakes
    )

    assert plan[:pose]
    landed = actor.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
    refute BF.rectangles_overlap?(landed, lake_obs)
  end

  test "unit already north of the lake wheels along the shore instead of reversing" do
    actor = BattleScenarios.combatant(
      x: 13.91, y: 11.803, facing: 16.65, movement: 4.0, base_width: 5.0, base_depth: 2.0
    )
    target = BattleScenarios.enemy(x: 31.0, y: 19.0, facing: 180.0, base_width: 4.0, base_depth: 4.0)
    lake = PathingAudit.wide_lake
    obstacles = Pathing.merge_obstacles([ actor, target ], [ lake ])
    lake_obs = BF.feature_as_obstacle(lake)
    plan = Pathing.plan_approach(
      origin: actor, goal_point: target, budget: 8.0,
      obstacles: obstacles, contact_id: target[:entity_id], goal_unit: target, terrain: [ lake ]
    )

    assert plan[:pose]
    landed = actor.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
    refute BF.rectangles_overlap?(landed, lake_obs)
    assert Pathing.meaningful_progress?(actor, plan[:pose]), "expected a shore wheel, got a hold"
    assert_operator landed[:x], :>=, actor[:x] - 0.05
    BattleInvariants.verify_pathing_plan!(
      actor, plan, obstacles: obstacles, budget: 8.0, contact_id: target[:entity_id]
    )
  end

  test "a spanning wall stops the unit instead of oscillating" do
    actor = BattleScenarios.combatant(x: 6.0, y: 12.0, facing: 0.0, movement: 4.0)
    target = BattleScenarios.enemy(x: 32.0, y: 12.0, facing: 180.0)
    wall = BattleScenarios.terrain(id: "wall", x: 20.0, y: 12.0, width: 24.0, depth: 4.0)
    obstacles = Pathing.merge_obstacles([ actor, target ], [ wall ])
    first = Pathing.plan_approach(
      origin: actor, goal_point: target, budget: 8.0,
      obstacles: obstacles, contact_id: target[:entity_id], goal_unit: target, terrain: [ wall ]
    )
    assert first[:pose]
    landed = actor.merge(x: first[:pose][:x], y: first[:pose][:y], facing: first[:pose][:facing])
    wall_obs = BF.feature_as_obstacle(wall)
    refute BF.rectangles_overlap?(landed, wall_obs)
    second = Pathing.plan_approach(
      origin: landed, goal_point: target, budget: 8.0,
      obstacles: Pathing.merge_obstacles([ landed, target ], [ wall ]),
      contact_id: target[:entity_id], goal_unit: target, terrain: [ wall ]
    )
    if second[:pose]
      again = landed.merge(x: second[:pose][:x], y: second[:pose][:y], facing: second[:pose][:facing])
      refute_operator again[:x], :<, landed[:x] - 0.5
      refute BF.rectangles_overlap?(again, wall_obs)
    end
  end

  test "audit meets the three-reviewer bar once pathing is honest" do
    report = PathingAudit.report

    assert report.meets_bar?, audit_failure_message(report)
  end

  private

  def audit_failure_message(report)
    lines = [
      "Linus #{report.linus}% Dijkstra #{report.dijkstra}% Maneuver #{report.maneuver}%",
      "bar Linus/Dijkstra #{PathingAudit::BAR[:linus]}% Maneuver #{PathingAudit::BAR[:maneuver]}%"
    ]
    report.issues.each { |issue| lines << "- #{issue[:id]}: #{issue[:message]}" }
    lines.join("\n")
  end
end
