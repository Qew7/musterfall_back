require "test_helper"

class BalanceSyntheticPlayTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    @catalog = Sim::Catalog::Loader.load
    @version = CatalogVersion.current!
    @run = BalanceSimulationRun.create!(
      catalog_version: @version,
      status: "running",
      config: {
        round: 1,
        budget_mode: "fixed",
        target_points: 300,
        hero_level: 1
      },
      seed: 42_001
    )
    @rng = Sim::Rng::Seeded.new(99)
  end

  test "plays synthetic battle into balance audit" do
    Balance::Synthetic::Play.call!(run: @run, catalog: @catalog, rng: @rng)

    rollup = BalanceBattleRollup.order(:id).last
    assert_equal "synthetic", rollup.source
    assert_equal @run.id, rollup.balance_simulation_run_id
    assert rollup.metrics["winner_faction"].present?
    assert BalanceCounter.exists?(bucket: "battle", key: "total")
  end
end
