require "test_helper"

class BalanceSimulationWorkerJobTest < ActiveJob::TestCase
  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    @version = CatalogVersion.current!
    @catalog = Sim::Catalog::Loader.load
  end

  test "worker completes limited run and finalizes after all workers finish" do
    run = BalanceSimulationRun.create!(
      catalog_version: @version,
      status: "running",
      config: { battle_limit: 2, workers_total: 2, workers_finished: 0 },
      seed: 42_002,
      started_at: Time.current
    )

    BalanceSimulationWorkerJob.perform_now(run.id)
    BalanceSimulationWorkerJob.perform_now(run.id)

    run.reload
    assert_equal "completed", run.status
    assert_equal 2, run.battles_completed
    assert run.finished_at.present?
  end

  test "worker honors stopping status" do
    run = BalanceSimulationRun.create!(
      catalog_version: @version,
      status: "stopping",
      config: { battle_limit: 100, workers_total: 1, workers_finished: 0 },
      seed: 42_003,
      started_at: Time.current
    )

    BalanceSimulationWorkerJob.perform_now(run.id)

    run.reload
    assert_equal "stopped", run.status
    assert_equal 0, run.battles_completed
  end
end
