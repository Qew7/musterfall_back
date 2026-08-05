require "test_helper"

class SimBattleScenarioFoundationTest < ActiveSupport::TestCase
  test "shared builders return isolated complete combatants" do
    first = BattleScenarios.combatant(entity_id: "first", abilities: [ "flying" ])
    second = BattleScenarios.combatant(entity_id: "second")

    first[:abilities] << "fear"

    assert_equal "first", first[:entity_id]
    assert_equal [], second[:abilities]
    assert second.key?(:contributors)
    assert second.key?(:models_remaining)
  end

  test "runner executes a movement scenario without exposing planner classes" do
    actor = BattleScenarios.combatant(x: 8.0, y: 12.0, movement: 4.0)
    target = BattleScenarios.enemy(x: 24.0, y: 12.0)
    scenario = BattleScenarios.scenario(
      id: "straight-approach",
      left: actor,
      right: target,
      reachable: true
    )

    result = BattleScenarioRunner.new(scenario).run_movement_phase

    assert_equal "straight-approach", result.scenario[:id]
    assert result.actions.any? { |action| action[:actor_id] == actor[:entity_id] }
    assert_operator result.actor[:x], :>, actor[:x]
  end
end
