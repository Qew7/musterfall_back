# frozen_string_literal: true

require "test_helper"

class BalanceBattleReportTest < ActiveSupport::TestCase
  test "build returns battles and duels summary without heavy buckets" do
    version = CatalogVersion.current!
    BalanceBattleRollup.create!(
      catalog_version: version,
      matchup_type: "pvb",
      source: "campaign",
      metrics: {
        winner_faction: "wildwood",
        left_faction: "wildwood",
        right_faction: "empire",
        rounds: 3,
        upset: true,
        left_army_cost: 5,
        right_army_cost: 10
      }
    )
    BalanceCounter.create!(
      catalog_version: version,
      bucket: "battle",
      key: "total",
      matchup_type: "all",
      n: 1,
      sum: 0
    )
    BalanceCounter.create!(
      catalog_version: version,
      bucket: "upset",
      key: "lower_cost_wins",
      matchup_type: "all",
      n: 1,
      sum: 0
    )
    BalanceCounter.create!(
      catalog_version: version,
      bucket: "faction_win",
      key: "wildwood",
      matchup_type: "all",
      n: 1,
      sum: 0
    )

    left = ArmyTemplate.find_by!(template_key: "state_swords")
    right = ArmyTemplate.find_by!(template_key: "orc_brutes")
    BalanceDuelRun.create!(
      catalog_version: version,
      left_template: left.template_key,
      right_template: right.template_key,
      contact: "front",
      iterations: 10,
      left_wins: left.cost < right.cost ? 8 : 2,
      right_wins: left.cost < right.cost ? 2 : 8,
      left_winrate: 0.8,
      right_winrate: 0.2,
      avg_rounds: 3,
      config: { "deploy" => "ranged" }
    )

    payload = Balance::BattleReport.build(matchup_type: "all", deploy: "ranged")

    assert_equal version.id, payload[:catalog_version_id]
    assert_equal 1, payload[:battles][:summary][:upset_count]
    assert_equal 1, payload[:battles][:faction_wins].first[:wins]
    assert payload[:duels][:summary].key?(:upset_count)
    assert_not payload.key?(:damage_matrix)
  end
end
