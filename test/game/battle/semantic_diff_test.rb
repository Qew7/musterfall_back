require "test_helper"

class SimBattleSemanticDiffTest < ActiveSupport::TestCase
  test "semantic snapshot ignores volatile ids and player-facing text" do
    stored = report(battle_id: "old", summary: "old wording", details: [ "old debug" ])
    fresh = report(battle_id: "new", summary: "new wording", details: [ "new debug" ])

    diff = Sim::Battle::SemanticDiff.call(stored, fresh)

    assert diff[:identical]
    assert_nil diff[:first_divergence]
  end

  test "semantic diff reports the first changed action field" do
    stored = report(to_x: 10.0)
    fresh = report(to_x: 12.0)

    diff = Sim::Battle::SemanticDiff.call(stored, fresh)

    refute diff[:identical]
    assert_includes diff[:categories_changed], :actions
    assert_equal "R1/T1/movement/A1.to", diff.dig(:first_divergence, :path)
  end

  test "semantic snapshot records rule effects without Ruby module names" do
    value = report(trace: { version: 1, rule_keys: [ "flying", "march" ], result: "applied" })

    snapshot = Sim::Battle::SemanticSnapshot.build(value)

    assert_equal({ "flying" => 1, "march" => 1 }, snapshot[:rule_effects])
    assert_equal %w[flying march], snapshot.dig(:actions, 0, :trace, :rule_keys)
  end

  private

  def report(battle_id: "battle", summary: "summary", details: [], to_x: 10.0, trace: nil)
    action = {
      type: "movement",
      actor_id: "unit-1",
      summary: summary,
      details: details,
      from: { x: 5.0, y: 12.0, facing: 0.0 },
      to: { x: to_x, y: 12.0, facing: 0.0 },
      maneuver: { kind: "march", target_id: "enemy-1" }
    }
    action[:trace] = trace if trace
    {
      battle_id: battle_id,
      winner_id: "left",
      summary: summary,
      left: { combatants: [ { current_health: 8 } ] },
      right: { combatants: [ { current_health: 6 } ] },
      rounds: [
        {
          turns: [
            {
              phases: [
                { type: "movement", actions: [ action ] }
              ]
            }
          ]
        }
      ]
    }
  end
end
