require "test_helper"

class BalanceRollupTest < ActiveSupport::TestCase
  setup do
    @catalog_version = CatalogVersion.current!
    @attacker = {
      id: "player-1",
      faction_id: "wildwood",
      is_bot: false,
      roster: [
        { id: "unit-1", template_id: "war_dancers", components: { economy: { cost: 10 } } }
      ]
    }
    @defender = {
      id: "player-2",
      faction_id: "ironbound",
      is_bot: true,
      roster: [
        { id: "unit-2", template_id: "grove_hawk", components: { economy: { cost: 8 } } }
      ]
    }
    @result = {
      winner_id: "player-1",
      left: {
        player_id: "player-1",
        combatants: [
          { entity_id: "unit-1", starting_models: 4, models_remaining: 3, current_health: 3 }
        ]
      },
      right: {
        player_id: "player-2",
        combatants: [
          { entity_id: "unit-2", starting_models: 3, models_remaining: 0, current_health: 0 }
        ]
      },
      rounds: [
        {
          turns: [
            {
              phases: [
                {
                  type: "melee",
                  actions: [
                    {
                      type: "melee",
                      actor_id: "unit-1",
                      target_id: "unit-2",
                      damage: 6,
                      trace: { rule_keys: [ "dodge" ], result: "hit" }
                    }
                  ]
                },
                {
                  type: "morale",
                  actions: [
                    {
                      type: "morale",
                      actor_id: "unit-2",
                      check: { passed: false },
                      trace: { result: "routed" }
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  end

  test "builds faction, damage and rule counters" do
    payload = Balance::Rollup.build(
      result: @result,
      attacker: @attacker,
      defender: @defender,
      catalog_version_id: @catalog_version.id
    )

    metrics = payload[:metrics]
    assert_equal "pvb", metrics[:matchup_type]
    assert_equal "wildwood", metrics[:winner_faction]
    assert_equal 6, metrics[:damage_matrix]["war_dancers->grove_hawk"]["melee"]
    assert_equal 1, metrics[:rule_triggers]["dodge"]
    assert_equal 3, metrics[:models_lost]["grove_hawk"]

    keys = payload[:counters].map { |row| [ row[:bucket], row[:key], row[:matchup_type] ] }
    assert_includes keys, [ "faction_win", "wildwood", "pvb" ]
    assert_includes keys, [ "damage", "war_dancers->grove_hawk:melee", "all" ]
  end

  test "persist writes rollup and increments counters" do
    Balance::Persist.call!(
      result: @result,
      attacker: @attacker,
      defender: @defender,
      catalog_version: @catalog_version,
      game_id: nil
    )

    assert_equal 1, BalanceBattleRollup.count
    assert BalanceCounter.exists?(bucket: "faction_win", key: "wildwood", matchup_type: "all")
    assert_equal 1, BalanceCounter.find_by!(bucket: "battle", key: "total", matchup_type: "all").n
  end
end
