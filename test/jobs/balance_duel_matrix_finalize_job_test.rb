require "test_helper"

class BalanceDuelMatrixFinalizeJobTest < ActiveJob::TestCase
  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    @version = CatalogVersion.current!
  end

  test "finalizes stopping run" do
    run = BalanceDuelMatrixRun.create!(
      catalog_version: @version,
      status: "stopping",
      config: { contact: "front", deploy: "ranged", random_first_turn: true, iterations: 2, batch_size: 10 },
      unit_templates: %w[state_swords handgunners],
      seed: 42_006,
      batches_total: 1,
      matchups_total: 1,
      started_at: Time.current
    )

    BalanceDuelMatrixFinalizeJob.perform_now(run.id)

    run.reload
    assert_equal "stopped", run.status
    assert run.finished_at.present?
  end
end
