require "test_helper"

class BalanceDashboardTest < ActiveSupport::TestCase
  test "all matchup filter uses only aggregate counters" do
    version = CatalogVersion.current!
    BalanceCounter.where(catalog_version: version, bucket: "faction_win", key: "undead").delete_all

    BalanceCounter.create!(
      catalog_version: version, bucket: "faction_win", key: "undead", matchup_type: "all", n: 50, sum: 0
    )
    BalanceCounter.create!(
      catalog_version: version, bucket: "faction_win", key: "undead", matchup_type: "bvb", n: 30, sum: 0
    )
    BalanceCounter.create!(
      catalog_version: version, bucket: "faction_win", key: "undead", matchup_type: "pvb", n: 20, sum: 0
    )

    payload = Balance::Dashboard.build(catalog_version_id: version.id, matchup_type: "all")
    undead_rows = payload[:faction_wins].select { |row| row[:faction_id] == "undead" }

    assert_equal 1, undead_rows.length
    assert_equal 50, undead_rows.first[:wins]
    assert_in_delta 1.0, undead_rows.first[:winrate], 0.001
  end
end
