require "test_helper"

class BalanceMorningSimulationJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    BalanceSimulationRun.update_all(status: "completed", finished_at: Time.current)
    BalanceDuelMatrixRun.update_all(status: "completed", finished_at: Time.current)
    @previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_adapter
    clear_enqueued_jobs
  end

  test "starts balanced random simulation with 1000 battles at 1000 points" do
    assert_difference -> { BalanceSimulationRun.count }, 1 do
      assert_difference -> { BalanceDuelMatrixRun.count }, 1 do
        assert_enqueued_jobs Balance::Simulation.worker_count, only: BalanceSimulationJob do
          BalanceMorningSimulationJob.perform_now
        end
      end
    end

    run = BalanceSimulationRun.order(:id).last
    assert_equal "balanced_random", run.config["preset"]
    assert_equal 1000, run.config["battle_limit"]
    assert_equal 1000, run.config["target_points"]
    assert_equal "running", run.status
    assert_equal Balance::Simulation.worker_count, run.config["workers_total"]

    matrix = BalanceDuelMatrixRun.order(:id).last
    assert_equal "front", matrix.config["contact"]
    assert_equal "ranged", matrix.config["deploy"]
    assert_equal true, matrix.config["random_first_turn"]
    assert_equal 50, matrix.config["iterations"]
    assert_equal 10, matrix.config["batch_size"]
    assert_equal "running", matrix.status
    assert_operator enqueued_jobs.count { |job| job[:job] == BalanceDuelMatrixBatchJob }, :>, 0
  end

  test "starts army simulation while another simulation is active" do
    version = CatalogVersion.current!
    BalanceSimulationRun.create!(
      catalog_version: version,
      status: "running",
      config: { battle_limit: 1, workers_total: 4, workers_finished: 0 },
      seed: 1
    )

    assert_difference -> { BalanceSimulationRun.count }, 1 do
      assert_difference -> { BalanceDuelMatrixRun.count }, 1 do
        BalanceMorningSimulationJob.perform_now
      end
    end
  end

  test "starts duel matrix while another matrix is active" do
    version = CatalogVersion.current!
    BalanceDuelMatrixRun.create!(
      catalog_version: version,
      status: "running",
      config: { contact: "front", iterations: 1, batch_size: 10 },
      unit_templates: Balance::DuelMatrix.unit_template_keys,
      seed: 1,
      batches_total: 1,
      matchups_total: 1
    )

    assert_difference -> { BalanceDuelMatrixRun.count }, 1 do
      assert_difference -> { BalanceSimulationRun.count }, 1 do
        BalanceMorningSimulationJob.perform_now
      end
    end
  end
end
