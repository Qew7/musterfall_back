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

  test "a wrap heading turns when a wheel at this width cannot clear the friend" do
    actor = BattleScenarios.combatant(
      entity_id: "unit-11", x: 35.0, y: 19.0, facing: 180.0,
      base_width: 4.0, base_depth: 4.0, files: 2, ranks: 2, movement: 3.0
    )
    friend = BattleScenarios.combatant(
      entity_id: "hero-2", x: 31.0, y: 19.0, facing: 180.0,
      base_width: 1.0, base_depth: 1.0
    )
    enemy = BattleScenarios.enemy(entity_id: "unit-36", x: 8.0, y: 16.0, facing: 0.0)
    space = Pathing::Obstacles.merge([ actor, friend, enemy ], [])
    heading = 270.0

    refute space.wheel_clear?(actor, heading, contact_id: enemy[:entity_id])
    assert Maneuvers.turn_for?(actor, heading, 3.0, enemy, space, enemy[:entity_id])

    plan = Maneuvers.follow_segment(
      origin: actor,
      heading: heading,
      budget: 3.0,
      goal_point: { x: 34.25, y: 15.75 },
      goal_unit: nil,
      obstacles: space,
      contact_id: enemy[:entity_id],
      finish: enemy
    )

    assert_equal :turn, plan[:maneuver]
    assert plan[:turn]
    assert plan[:turn][:completed]
    assert_in_delta 270.0, plan[:pose][:facing], 0.5
    assert_operator plan[:pose][:y], :<, actor[:y]
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
