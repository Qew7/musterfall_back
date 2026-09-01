require "test_helper"

class Api::Admin::BalanceControllerTest < ActionDispatch::IntegrationTest
  test "show returns empty dashboard when no catalog versions" do
    CatalogVersion.delete_all

    get "/api/admin/balance"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["catalog_versions"]
    assert_equal 0, body["summary"]["battle_count"]
  end

  test "show returns dashboard payload" do
    version = CatalogVersion.current!
    BalanceBattleRollup.create!(
      catalog_version: version,
      matchup_type: "pvb",
      source: "campaign",
      metrics: {
        winner_faction: "wildwood",
        left_faction: "wildwood",
        right_faction: "ironbound",
        rounds: 3,
        upset: false,
        left_army_cost: 10,
        right_army_cost: 8
      }
    )
    BalanceCounter.create!(
      catalog_version: version,
      bucket: "faction_win",
      key: "wildwood",
      matchup_type: "all",
      n: 1,
      sum: 0
    )

    get "/api/admin/balance", params: { catalog_version_id: version.id, matchup_type: "all" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal version.id, body["selected_version_id"]
    assert_equal 1, body["faction_wins"].first["wins"]
    assert_equal 1, body["recent_battles"].length
  end

  test "backfill enqueues background job" do
    CatalogVersion.current!

    post "/api/admin/balance/backfill"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "started", body["status"]
  end
end
