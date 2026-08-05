require "test_helper"

class SimBattleMovementInvariantsTest < ActiveSupport::TestCase
  test "valid movement scenario satisfies shared invariants" do
    scenario = BattleScenarios.scenario(
      id: "valid-straight-move",
      left: BattleScenarios.combatant(x: 8.0, y: 12.0),
      right: BattleScenarios.enemy(x: 24.0, y: 12.0)
    )

    result = BattleScenarioRunner.new(scenario).run_movement_phase

    assert BattleInvariants.verify_result!(result)
  end

  test "invariants report unit and impassable terrain overlap" do
    unit = BattleScenarios.combatant(x: 20.0, y: 12.0)
    house = BattleScenarios.terrain(x: 20.0, y: 12.0, impassable: true)

    error = assert_raises(BattleInvariants::Violation) do
      BattleInvariants.verify_battlefield!(
        [ { combatants: [ unit ] } ],
        terrain: [ house ]
      )
    end

    assert_includes error.message, "impassable terrain"
  end

  test "invariants reject movement cost above recorded budget" do
    action = {
      type: "movement",
      actor_id: "unit-1",
      actor_state_before: {},
      actor_state_after: {},
      summary: "moves",
      details: [],
      from: { x: 0.0, y: 0.0, facing: 0.0 },
      to: { x: 5.0, y: 0.0, facing: 0.0 },
      maneuver: {
        kind: "march",
        mv_budget: 4.0,
        mv_spent_wheel: 1.0,
        mv_spent_march: 4.0
      }
    }

    error = assert_raises(BattleInvariants::Violation) do
      BattleInvariants.verify_movement_action!(action)
    end
    assert_includes error.message, "exceeds budget"
  end
end
