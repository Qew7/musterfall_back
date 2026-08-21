require "test_helper"

class SimBattleMovementManeuversTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  Pathing = Sim::Battle::Pathing
  Maneuvers = Sim::Battle::Pathing::Maneuvers

  test "aligned approach is an advance, not a wheel or march" do
    actor = BattleScenarios.combatant(x: 8.0, y: 12.0, facing: 0.0, movement: 4.0)
    enemy = BattleScenarios.enemy(x: 24.0, y: 12.0, facing: 180.0)
    plan = Maneuvers.follow_segment(
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
    plan = Maneuvers.follow_segment(
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
    plan = Maneuvers.follow_segment(
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

    plan = Maneuvers.follow_segment(
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
    plan = Maneuvers.follow_segment(
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

  test "a wrap heading does not reform when the enemy is ahead" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-12", x: 35.0, y: 19.0, facing: 180.0,
      base_width: 4.0, base_depth: 2.0, files: 4, ranks: 2, movement: 4.0
    )
    enemy = BattleScenarios.enemy(entity_id: "unit-37", x: 8.0, y: 20.0, facing: 0.0)
    space = Pathing::Obstacles.merge([ actor, enemy ], [])
    heading = 270.0

    refute Maneuvers.turn_for?(actor, heading, 4.0, enemy, space, enemy[:entity_id])

    plan = Maneuvers.follow_segment(
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

  test "follow does not reform onto a side waypoint when the enemy is ahead" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-10", x: 31.0, y: 11.0, facing: 180.0,
      base_width: 4.0, base_depth: 2.0, files: 4, ranks: 2, movement: 3.0
    )
    enemy = BattleScenarios.enemy(entity_id: "unit-38", x: 7.0, y: 7.0, facing: 0.0)
    thread = {
      points: [
        { x: 31.0, y: 11.0 },
        { x: 31.0, y: 9.5 }
      ],
      complete: false,
      wrapped: [ { entity_id: "terrain-4" } ]
    }
    plan = Pathing::Follow.along(
      origin: actor,
      thread: thread,
      budget: 3.0,
      goal_unit: enemy,
      obstacles: [ actor, enemy ],
      contact_id: enemy[:entity_id]
    )

    refute plan[:steps].any? { |step| step[:kind] == "turn" }
    refute BF.turn_delta?(BF.shortest_facing_delta(actor[:facing], plan[:pose][:facing])),
           "reformed onto wrap vertex facing=#{plan.dig(:pose, :facing)}"
  end

  test "follow skips a wrap vertex that doubles back when the enemy is ahead" do
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

    refute_equal :turn, plan[:maneuver], "reformed onto wrap vertex facing=#{plan.dig(:pose, :facing)}"
    refute BF.turn_delta?(BF.shortest_facing_delta(actor[:facing], plan[:pose][:facing])),
           "reformed onto wrap vertex facing=#{plan.dig(:pose, :facing)}"
    refute plan[:steps].any? { |step| step[:kind] == "turn" }
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
      goal_unit: nil,
      bypass: false
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
end
