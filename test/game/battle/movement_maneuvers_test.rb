require "test_helper"

class SimBattleMovementManeuversTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  Pathing = Sim::Battle::Pathing
  Maneuvers = Sim::Battle::Pathing::Maneuvers

  test "adjacent wheels in one direction are recorded as one maneuver" do
    first = {
      kind: "wheel",
      direction: "right",
      delta: 30.0,
      cost: 1.0,
      from: { x: 5.0, y: 5.0, facing: 0.0 },
      to: { x: 5.2, y: 5.1, facing: 30.0 }
    }
    second = {
      kind: "wheel",
      direction: "right",
      delta: 20.0,
      cost: 0.5,
      from: first[:to].dup,
      to: { x: 5.4, y: 5.3, facing: 50.0 }
    }

    compacted = Maneuvers.compact_motion_entries([ first, second ])

    assert_equal 1, compacted.size
    assert_in_delta 50.0, compacted.first[:delta], 0.001
    assert_in_delta 1.5, compacted.first[:cost], 0.001
    assert_equal second[:to], compacted.first[:to]
  end

  test "aligned approach is an advance, not a wheel or march" do
    actor = BattleScenarios.combatant(x: 8.0, y: 12.0, facing: 0.0, movement: 4.0)
    enemy = BattleScenarios.enemy(x: 24.0, y: 12.0, facing: 180.0)
    plan = Maneuvers.plan_segment(
      origin: actor,
      heading: 0.0,
      budget: 4.0,
      goal_point: enemy,
      goal_unit: enemy,
      obstacles: [ actor, enemy ],
      contact_id: enemy[:entity_id]
    )

    assert_equal :advance, plan[:maneuver]
    assert plan[:steps].any? { |step| step[:kind] == "advance" }
    refute plan[:steps].any? { |step| %w[wheel march].include?(step[:kind]) }
    refute plan[:turn]
  end

  test "aligned approach marches double distance when the tray is clear" do
    actor = BattleScenarios.combatant(x: 8.0, y: 12.0, facing: 0.0, movement: 4.0)
    enemy = BattleScenarios.enemy(x: 32.0, y: 12.0, facing: 180.0)
    plan = Maneuvers.plan_segment(
      origin: actor,
      heading: 0.0,
      budget: 4.0,
      goal_point: enemy,
      goal_unit: enemy,
      obstacles: [ actor, enemy ],
      contact_id: enemy[:entity_id],
      march_allowed: true
    )

    assert_equal :march, plan[:maneuver]
    assert_in_delta 8.0, plan[:pose][:x] - actor[:x], 0.2
    assert plan[:steps].any? { |step| step[:kind] == "march" }
  end

  test "a 90 degree heading on a wide tray is a turn onto the old flank" do
    actor = BattleScenarios.combatant(
      x: 8.0, y: 12.0, facing: 0.0, movement: 4.0,
      base_width: 5.0, base_depth: 2.0, files: 5, ranks: 2, frontage: 5
    )
    goal = { x: 8.0, y: 20.0 }
    plan = Maneuvers.plan_segment(
      origin: actor,
      heading: 90.0,
      budget: 4.0,
      goal_point: goal,
      goal_unit: nil,
      obstacles: [ actor ],
      contact_id: nil
    )

    assert_equal :turn, plan[:maneuver]
    assert plan[:turn]
    assert plan[:turn][:completed]
    assert_in_delta 2.0, plan[:turn][:cost], 0.001
    assert_in_delta 90.0, plan[:pose][:facing], 0.2
    assert_in_delta 2.0, plan[:pose][:base_width], 0.001
    assert_in_delta 5.0, plan[:pose][:base_depth], 0.001
    assert_equal 2, plan[:pose][:files]
    assert_equal 5, plan[:pose][:ranks]
    assert_operator plan[:pose][:y], :>, actor[:y] + 0.5
    assert plan[:steps].any? { |step| step[:kind] == "turn" }
  end

  test "a column reforms onto the old flank when the goal is a 90 degree hop and the wheel is clear" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-29", x: 4.0, y: 6.0, facing: 90.0, movement: 4.0,
      base_width: 2.0, base_depth: 4.0, files: 2, ranks: 4, frontage: 2
    )
    prince = BattleScenarios.combatant(
      entity_id: "hero-8", x: 14.19, y: 10.90, facing: 184.4,
      base_width: 1.0, base_depth: 2.0, files: 1, ranks: 1, current_health: 5
    )
    enemy = BattleScenarios.enemy(
      entity_id: "unit-32", x: 31.18, y: 16.11, facing: 174.9,
      base_width: 4.0, base_depth: 3.0, files: 4, ranks: 3, current_health: 10
    )
    space = Pathing::Obstacles.merge([ actor, prince, enemy ], [])
    heading = BF.heading_to(actor, { x: 10.70, y: 7.37 })
    finish = BF.charge_destination(actor, enemy)

    assert space.wheel_clear?(actor, heading, contact_id: enemy[:entity_id])
    assert Maneuvers::Turn.applies?(actor, BF.heading_to(actor, finish), 4.0)
    assert Maneuvers.turn_for?(actor, heading, 4.0, finish, space, enemy[:entity_id])

    plan = Pathing.plan_approach(
      origin: actor, goal_point: enemy, budget: 4.0,
      obstacles: space, contact_id: enemy[:entity_id], goal_unit: enemy
    )
    landed = BF.merge_footprint(actor, plan[:pose])

    assert_equal :turn, plan[:maneuver]
    assert_in_delta 0.0, landed[:facing], 8.0
    assert_in_delta 4.0, landed[:base_width], 0.001
    assert_in_delta 2.0, landed[:base_depth], 0.001
    assert_equal 4, landed[:files]
    assert_equal 2, landed[:ranks]
    assert_operator landed[:x], :>, actor[:x] + 0.5
  end

  test "a 50 degree correction still wheels instead of turning" do
    actor = BattleScenarios.combatant(
      x: 8.0, y: 12.0, facing: 40.0, movement: 3.0,
      base_width: 4.0, base_depth: 1.0, files: 4, ranks: 1
    )
    heading = 90.0
    refute Maneuvers::Turn.applies?(actor, heading, 3.0)
    assert Maneuvers::Wheel.applies?(actor, heading, 3.0)

    plan = Maneuvers.plan_segment(
      origin: actor,
      heading: heading,
      budget: 3.0,
      goal_point: { x: 8.0, y: 20.0 },
      goal_unit: nil,
      obstacles: [ actor ],
      contact_id: nil
    )

    assert_equal :wheel, plan[:maneuver]
    assert plan[:wheel]
    assert_operator plan[:wheel][:cost].to_f, :>, 0.05
  end

  test "a 90 degree heading after the first segment wheels instead of turning" do
    actor = BattleScenarios.combatant(
      x: 8.0, y: 12.0, facing: 0.0, movement: 4.0,
      base_width: 5.0, base_depth: 2.0, files: 5, ranks: 2, frontage: 5
    )
    plan = Maneuvers.plan_segment(
      origin: actor,
      heading: 90.0,
      budget: 4.0,
      goal_point: { x: 8.0, y: 20.0 },
      goal_unit: nil,
      obstacles: [ actor ],
      contact_id: nil,
      allow_turn: false
    )

    assert_equal :wheel, plan[:maneuver]
    refute plan[:turn]
    assert plan[:steps].any? { |step| step[:kind] == "wheel" }
    refute plan[:steps].any? { |step| step[:kind] == "turn" }
  end

  test "a route heading does not reform when the enemy is ahead" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-12", x: 35.0, y: 19.0, facing: 180.0,
      base_width: 4.0, base_depth: 2.0, files: 4, ranks: 2, movement: 4.0
    )
    enemy = BattleScenarios.enemy(entity_id: "unit-37", x: 8.0, y: 20.0, facing: 0.0)
    space = Pathing::Obstacles.merge([ actor, enemy ], [])
    heading = 270.0

    refute Maneuvers.turn_for?(actor, heading, 4.0, enemy, space, enemy[:entity_id])

    plan = Maneuvers.plan_segment(
      origin: actor,
      heading: heading,
      budget: 4.0,
      goal_point: { x: 35.0, y: 17.0 },
      goal_unit: nil,
      obstacles: space,
      contact_id: enemy[:entity_id],
      finish: enemy
    )

    refute_equal :turn, plan[:maneuver]
    refute plan[:turn]
    refute BF.turn_delta?(BF.shortest_facing_delta(actor[:facing], plan[:pose][:facing]))
  end

  test "maneuver sequence does not reform onto a side waypoint when the enemy is ahead" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-10", x: 31.0, y: 11.0, facing: 180.0,
      base_width: 4.0, base_depth: 2.0, files: 4, ranks: 2, movement: 3.0
    )
    enemy = BattleScenarios.enemy(entity_id: "unit-38", x: 7.0, y: 7.0, facing: 0.0)
    route = {
      points: [
        { x: 31.0, y: 11.0 },
        { x: 31.0, y: 9.5 }
      ],
      complete: false
    }
    plan = Pathing::ManeuverSequence.along(
      origin: actor,
      route: route,
      budget: 3.0,
      goal_unit: enemy,
      obstacles: [ actor, enemy ],
      contact_id: enemy[:entity_id]
    )

    refute plan[:steps].any? { |step| step[:kind] == "turn" }
    refute BF.turn_delta?(BF.shortest_facing_delta(actor[:facing], plan[:pose][:facing])),
           "reformed onto route point facing=#{plan.dig(:pose, :facing)}"
  end

  test "route turns 90 when a wheel into CONTACT-kissing terrain cannot start" do
    actor = BattleScenarios.combatant(
      entity_id: "hero-1", x: 11.81, y: 15.36, facing: 313.4,
      base_width: 1.0, base_depth: 1.0, files: 1, ranks: 1, frontage: 1, movement: 3.0
    )
    enemy = BattleScenarios.enemy(
      entity_id: "unit-20", x: 30.66, y: 6.24, facing: 218.4,
      base_width: 4.0, base_depth: 2.0
    )
    lake = BattleScenarios.terrain(
      id: "terrain-2", type: "lake", x: 14.76, y: 13.16, width: 3.74, depth: 3.99
    )
    world = Pathing::Obstacles.merge([ actor, enemy ], [ lake ])
    plan = Pathing.plan_approach(
      origin: actor, goal_point: enemy, budget: 3.0,
      obstacles: world, contact_id: enemy[:entity_id], goal_unit: enemy, terrain: [ lake ]
    )

    assert plan[:steps].any? { |step| step[:kind] == "turn" },
           "expected a 90° reform, got #{Array(plan[:steps]).map { |step| step[:kind] }}"
    landed = BF.merge_footprint(actor, plan[:pose])
    refute BF.rectangles_overlap?(landed, BF.feature_as_obstacle(lake))
    assert_operator BF.distance_between(actor, plan[:pose]), :>, 0.2
  end

  test "route may turn around terrain while still closing on the enemy" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-10", x: 31.0, y: 11.0, facing: 180.0,
      base_width: 4.0, base_depth: 2.0, files: 4, ranks: 2, movement: 3.0
    )
    enemy = BattleScenarios.enemy(entity_id: "unit-38", x: 7.0, y: 7.0, facing: 0.0)
    house = BattleScenarios.terrain(
      id: "terrain-4", type: "house", x: 26.496, y: 7.603, width: 3.421, depth: 2.688
    )
    world = Pathing::Obstacles.merge([ actor, enemy ], [ house ])
    plan = Pathing.plan_approach(
      origin: actor, goal_point: enemy, budget: 3.0,
      obstacles: world, contact_id: enemy[:entity_id], goal_unit: enemy, terrain: [ house ]
    )

    assert_operator BF.distance_between(plan[:pose], enemy), :<, BF.distance_between(actor, enemy)
    refute BF.rectangles_overlap?(BF.merge_footprint(actor, plan[:pose]), BF.feature_as_obstacle(house))
  end

  test "movement phase applies the turned footprint to the combatant" do
    actor = BattleScenarios.combatant(
      entity_id: "block-1",
      name: "Стража",
      x: 8.0,
      y: 12.0,
      facing: 0.0,
      movement: 4.0,
      base_width: 5.0,
      base_depth: 2.0,
      files: 5,
      ranks: 2,
      frontage: 5,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "center"
    )
    enemy = BattleScenarios.enemy(
      x: 8.0,
      y: 20.0,
      facing: 270.0,
      base_width: 2.0,
      base_depth: 2.0
    )
    # Force a 90° heading through pathing even if the planner would skip out-of-arc targets.
    plan = Pathing.plan_approach(
      origin: actor,
      goal_point: enemy,
      budget: 4.0,
      obstacles: [ actor, enemy ],
      contact_id: nil,
      goal_unit: nil
    )

    assert_equal :turn, plan[:maneuver], "expected turn, got #{plan[:maneuver].inspect} facing=#{plan.dig(:pose, :facing)}"

    intent = {
      kind: "approach",
      combatant: actor,
      nearest: enemy,
      plan: plan,
      budget: 4.0,
      destination: plan[:pose],
      wait: false
    }
    Sim::Battle::Phases::Movement.apply_intents!([ intent ])

    assert_in_delta 90.0, actor[:facing], 1.0
    assert_in_delta 2.0, actor[:base_width], 0.001
    assert_in_delta 5.0, actor[:base_depth], 0.001
    assert_equal 2, actor[:files]
    assert_equal 5, actor[:ranks]
  end

  test "a column turns onto the wider face when the corridor fits and the enemy can charge" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-col", x: 10.0, y: 12.0, facing: 90.0, movement: 4.0,
      base_width: 2.0, base_depth: 5.0, files: 2, ranks: 5, frontage: 5
    )
    enemy = BattleScenarios.enemy(
      entity_id: "unit-en", x: 18.0, y: 12.0, facing: 180.0, movement: 4.0,
      base_width: 4.0, base_depth: 2.0
    )
    world = Pathing::Obstacles.merge([ actor, enemy ], [])

    assert Pathing.widening_turn?(actor, enemy, world, 4.0, contact_id: enemy[:entity_id])

    intent = Sim::Battle::Rules::Ground::Movement.build_approach_intent(
      combatant: actor, nearest: enemy, obstacles: world, enemies: [ enemy ],
      contact_slot: "front", terrain: []
    )
    landed = BF.merge_footprint(actor, intent[:destination])

    assert intent[:plan][:turn]
    assert_in_delta 0.0, landed[:facing], 15.0
    assert_in_delta 5.0, landed[:base_width], 0.001
    assert_equal 5, landed[:files]
    assert_equal 2, landed[:ranks]
  end

  test "a column stays narrow when the corridor is thinner than the restored front" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-col", x: 10.0, y: 12.0, facing: 90.0, movement: 4.0,
      base_width: 2.0, base_depth: 5.0, files: 2, ranks: 5, frontage: 5
    )
    enemy = BattleScenarios.enemy(
      entity_id: "unit-en", x: 18.0, y: 12.0, facing: 180.0, movement: 4.0,
      base_width: 4.0, base_depth: 2.0
    )
    north = BattleScenarios.terrain(
      id: "lake-n", type: "lake", x: 14.0, y: 8.0, width: 4.0, depth: 4.0
    )
    south = BattleScenarios.terrain(
      id: "lake-s", type: "lake", x: 14.0, y: 16.0, width: 4.0, depth: 4.0
    )
    world = Pathing::Obstacles.merge([ actor, enemy ], [ north, south ])

    refute Pathing.widening_turn?(actor, enemy, world, 4.0, contact_id: enemy[:entity_id])
  end

  test "a column widens toward an enemy who is not facing us when we can charge next turn" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-col", x: 10.0, y: 12.0, facing: 90.0, movement: 4.0,
      base_width: 2.0, base_depth: 5.0, files: 2, ranks: 5, frontage: 5
    )
    enemy = BattleScenarios.enemy(
      entity_id: "unit-en", x: 18.0, y: 12.0, facing: 0.0, movement: 4.0,
      base_width: 4.0, base_depth: 2.0
    )
    world = Pathing::Obstacles.merge([ actor, enemy ], [])

    refute BF.in_front_arc?(enemy, actor, enemy[:facing])
    assert Pathing.widening_turn?(actor, enemy, world, 4.0, contact_id: enemy[:entity_id])
  end

  test "a friend in the corridor does not block a widening turn" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-col", x: 10.0, y: 12.0, facing: 90.0, movement: 4.0,
      base_width: 2.0, base_depth: 5.0, files: 2, ranks: 5, frontage: 5
    )
    friend = BattleScenarios.combatant(
      entity_id: "hero-1", x: 14.0, y: 12.0, facing: 90.0,
      base_width: 1.0, base_depth: 1.0, files: 1, ranks: 1
    )
    enemy = BattleScenarios.enemy(
      entity_id: "unit-en", x: 20.0, y: 12.0, facing: 180.0, movement: 4.0,
      base_width: 4.0, base_depth: 2.0
    )
    world = Pathing::Obstacles.merge([ actor, friend, enemy ], [])

    assert Pathing.widening_turn?(actor, enemy, world, 4.0, contact_id: enemy[:entity_id])
  end

  test "a column facing a distant enemy does not spend a turn to widen" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-col", x: 6.0, y: 12.0, facing: 90.0, movement: 4.0,
      base_width: 2.0, base_depth: 5.0, files: 2, ranks: 5, frontage: 5
    )
    enemy = BattleScenarios.enemy(
      entity_id: "unit-en", x: 34.0, y: 12.0, facing: 0.0, movement: 4.0,
      base_width: 4.0, base_depth: 2.0
    )
    world = Pathing::Obstacles.merge([ actor, enemy ], [])

    refute Pathing.widening_turn?(actor, enemy, world, 4.0, contact_id: enemy[:entity_id])
  end
end
