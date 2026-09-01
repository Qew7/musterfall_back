require "test_helper"

class BalanceDuelDashboardTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    @version = CatalogVersion.current!
  end

  test "aggregates duel runs for selected catalog version" do
    BalanceDuelRun.create!(
      catalog_version: @version,
      left_template: "state_swords",
      right_template: "chaos_warriors",
      contact: "front",
      iterations: 10,
      left_wins: 6,
      right_wins: 4,
      left_winrate: 0.6,
      right_winrate: 0.4,
      avg_rounds: 5.0,
      config: {}
    )
    BalanceDuelRun.create!(
      catalog_version: @version,
      left_template: "state_swords",
      right_template: "chaos_warriors",
      contact: "front",
      iterations: 20,
      left_wins: 8,
      right_wins: 12,
      left_winrate: 0.4,
      right_winrate: 0.6,
      avg_rounds: 4.0,
      config: {}
    )

    payload = Balance::DuelDashboard.build(catalog_version_id: @version.id)

    assert_equal 2, payload[:summary][:duel_run_count]
    assert_equal 30, payload[:summary][:total_iterations]
    assert_equal 1, payload[:matchups].length
    assert_equal 14, payload[:matchups].first[:left_wins]
    assert_equal 16, payload[:matchups].first[:right_wins]
    assert_equal 2, payload[:template_wins].length
  end
end
