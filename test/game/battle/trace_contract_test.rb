require "test_helper"

class SimBattleTraceContractTest < ActiveSupport::TestCase
  test "trace is versioned and uses stable rule keys" do
    trace = Sim::Battle::Trace.build(
      rule_keys: [ :flying, "march", "flying" ],
      trigger: :movement_plan,
      result: :flyer_leap,
      target_ids: [ "enemy-1", nil ]
    )

    assert_equal 1, trace[:version]
    assert_equal %w[flying march], trace[:rule_keys]
    assert_equal "movement_plan", trace[:trigger]
    assert_equal "flyer_leap", trace[:result]
    assert_equal [ "enemy-1" ], trace[:target_ids]
  end

  test "movement actions expose applied movement abilities in trace" do
    flyer = BattleScenarios.combatant(
      entity_id: "flyer",
      movement: 10.0,
      abilities: [ "flying" ]
    )
    target = BattleScenarios.enemy(x: 30.0)
    result = BattleScenarioRunner.new(
      BattleScenarios.scenario(id: "trace-flying", left: flyer, right: target)
    ).run_movement_phase
    action = result.actions.find { |entry| entry[:actor_id] == "flyer" }

    assert_equal 1, action.dig(:trace, :version)
    assert_includes action.dig(:trace, :rule_keys), "flying"
    assert_equal target[:entity_id], action.dig(:trace, :target_ids, 0)
  end

  test "battle persistence keeps trace as camelCase JSON data" do
    writer = Sim::Persistence::BattleWriter.new(nil)
    action = {
      type: "movement",
      trace: {
        version: 1,
        rule_keys: [ "march" ],
        target_ids: [ "enemy-1" ]
      }
    }

    persisted = writer.send(:deep_stringify, action)

    assert_equal 1, persisted.dig("trace", "version")
    assert_equal [ "march" ], persisted.dig("trace", "ruleKeys")
    assert_equal [ "enemy-1" ], persisted.dig("trace", "targetIds")
  end
end
