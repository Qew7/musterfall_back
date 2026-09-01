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

  test "units returns empty dashboard when no catalog versions" do
    CatalogVersion.delete_all

    get "/api/admin/balance/units"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["catalog_versions"]
    assert_equal 0, body["summary"]["duel_run_count"]
  end

  test "units returns duel dashboard payload" do
    version = CatalogVersion.current!
    BalanceDuelRun.create!(
      catalog_version: version,
      left_template: "state_swords",
      right_template: "chaos_warriors",
      contact: "front",
      iterations: 5,
      left_wins: 3,
      right_wins: 2,
      left_winrate: 0.6,
      right_winrate: 0.4,
      avg_rounds: 4.5,
      config: {}
    )

    get "/api/admin/balance/units", params: { catalog_version_id: version.id }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal version.id, body["selected_version_id"]
    assert_equal 1, body["summary"]["duel_run_count"]
    assert_equal 1, body["recent_runs"].length
  end

  test "start duel matrix creates run" do
    CatalogVersion.current!
    BalanceDuelMatrixRun.delete_all
    templates = Balance::DuelMatrix.unit_template_keys.first(4)
    original = Balance::DuelMatrix.method(:unit_template_keys)
    Balance::DuelMatrix.singleton_class.define_method(:unit_template_keys) { templates }

    post "/api/admin/balance/duel_matrix", params: { contact: "front", iterations: 2, batch_size: 2 }

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal 2, body["run"]["batches_total"]
    assert_equal 6, body["run"]["matchups_total"]
  ensure
    Balance::DuelMatrix.singleton_class.define_method(:unit_template_keys, original)
  end

  test "stop all simulations stops every active run" do
    version = CatalogVersion.current!
    running = BalanceSimulationRun.create!(
      catalog_version: version,
      status: "running",
      config: { battle_limit: 10 },
      seed: 1,
      started_at: Time.current
    )
    pending = BalanceSimulationRun.create!(
      catalog_version: version,
      status: "pending",
      config: { battle_limit: 10 },
      seed: 2
    )

    post "/api/admin/balance/simulations/stop"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 2, body["runs"].length
    assert_equal "stopping", running.reload.status
    assert_equal "stopped", pending.reload.status
  end
end
