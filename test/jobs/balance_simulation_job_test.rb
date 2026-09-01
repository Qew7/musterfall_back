require "test_helper"

class BalanceSimulationJobTest < ActiveJob::TestCase
  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    @version = CatalogVersion.current!
  end

  test "sync job completes limited run" do
    run = BalanceSimulationRun.create!(
      catalog_version: @version,
      status: "running",
      config: { battle_limit: 2, workers_total: 1, workers_finished: 0 },
      seed: 42_004,
      started_at: Time.current
    )

    BalanceSimulationJob.perform_now(run.id)

    run.reload
    assert_equal "completed", run.status
    assert_equal 2, run.battles_completed
  end
end
