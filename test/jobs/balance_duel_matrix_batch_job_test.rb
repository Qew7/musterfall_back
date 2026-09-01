require "test_helper"

class BalanceDuelMatrixBatchJobTest < ActiveJob::TestCase
  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    @version = CatalogVersion.current!
    @templates = Balance::DuelMatrix.unit_template_keys.sort.first(3)
  end

  test "processes batch and persists duel runs" do
    run = BalanceDuelMatrixRun.create!(
      catalog_version: @version,
      status: "running",
      config: { contact: "front", deploy: "ranged", random_first_turn: true, iterations: 2, batch_size: 10 },
      unit_templates: @templates,
      seed: 42_003,
      batches_total: 1,
      matchups_total: 3,
      started_at: Time.current
    )
    before = BalanceDuelRun.count

    BalanceDuelMatrixBatchJob.perform_now(run.id, 0, @templates, @templates)

    run.reload
    assert_equal 1, run.batches_completed
    assert_equal "completed", run.status
    assert_equal 3, run.matchups_completed
    assert_operator BalanceDuelRun.count, :>, before
    assert_equal "ranged", BalanceDuelRun.last.config["deploy"]
    assert_equal true, BalanceDuelRun.last.config["random_first_turn"]
  end

  test "batch job uses ranged deploy for all pairs" do
    templates = %w[state_swords handgunners orc_brutes]
    run = BalanceDuelMatrixRun.create!(
      catalog_version: @version,
      status: "running",
      config: { contact: "front", deploy: "ranged", random_first_turn: true, iterations: 1, batch_size: 10 },
      unit_templates: templates,
      seed: 42_004,
      batches_total: 1,
      matchups_total: 3,
      started_at: Time.current
    )
    before_ids = BalanceDuelRun.pluck(:id)

    BalanceDuelMatrixBatchJob.perform_now(run.id, 0, templates, templates)

    new_runs = BalanceDuelRun.where.not(id: before_ids)
    assert_equal 3, new_runs.count
    assert new_runs.all? { |entry| entry.config["deploy"] == "ranged" }
  end
end
