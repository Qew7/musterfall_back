require "test_helper"

class BalanceDuelMatrixTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    @templates = Balance::DuelMatrix.unit_template_keys.sort
  end

  test "pairs_for_batch skips duplicate matchups" do
    templates = %w[a b c d]
    pairs = Balance::DuelMatrix.pairs_for_batch(templates, %w[a b])

    assert_equal [ [ "a", "b" ], [ "a", "c" ], [ "a", "d" ], [ "b", "c" ], [ "b", "d" ] ], pairs
  end

  test "plan_batches splits anchors" do
    batches = Balance::DuelMatrix.plan_batches(%w[a b c d e], batch_size: 2)

    assert_equal 3, batches.length
    assert_equal %w[a b], batches[0][:anchors]
    assert_equal %w[c d], batches[1][:anchors]
    assert_equal [ "e" ], batches[2][:anchors]
  end

  test "start creates matrix run and processes batches" do
    BalanceDuelMatrixRun.delete_all
    templates = @templates.first(4)
    original = Balance::DuelMatrix.method(:unit_template_keys)
    Balance::DuelMatrix.singleton_class.define_method(:unit_template_keys) { templates }

    run = Balance::DuelMatrix.start!(config: { contact: "front", iterations: 2, batch_size: 2 })

    assert_equal 2, run.batches_total
    assert_equal 6, run.matchups_total
    assert_equal "ranged", run.config["deploy"]
    assert_equal true, run.config["random_first_turn"]
    assert_includes %w[running completed], run.reload.status
    assert_operator BalanceDuelRun.count, :>, 0
  ensure
    Balance::DuelMatrix.singleton_class.define_method(:unit_template_keys, original)
  end

  test "normalize_config defaults deploy to ranged with random first turn" do
    config = Balance::DuelMatrix.normalize_config({ contact: "front", iterations: 10 })

    assert_equal "ranged", config[:deploy]
    assert_equal true, config[:random_first_turn]
  end

  test "stop finalizes stopping run immediately" do
    run = BalanceDuelMatrixRun.create!(
      catalog_version: CatalogVersion.current!,
      status: "running",
      config: { contact: "front", deploy: "ranged", random_first_turn: true, iterations: 2, batch_size: 10 },
      unit_templates: @templates.first(3),
      seed: 42_005,
      batches_total: 1,
      matchups_total: 3,
      started_at: Time.current
    )

    Balance::DuelMatrix.stop!(run.id)

    assert_equal "stopped", run.reload.status
    assert run.finished_at.present?
  end
end
