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

  test "staged battle persists the actual stage and troop budgets" do
    @run.update!(config: @run.config.merge("army_stage" => "mixed"))
    Balance::Synthetic::Play.call!(run: @run, catalog: @catalog, rng: @rng, battle_no: 3)
    metrics = BalanceBattleRollup.order(:id).last.metrics
    assert_equal "early", metrics["army_stage"]
    assert_equal 625, metrics["left_budget"]
    assert_equal 625, metrics["right_budget"]
    assert_equal 1, metrics["hero_level"]
    %w[left right].each do |side|
      recruitment = metrics.fetch("#{side}_recruitment")
      assert_equal 625, recruitment["spent"] + recruitment["unspent"]
      assert_equal 0, recruitment["access"]
      assert_operator recruitment["roster_size"], :<=, 12
    end
  end
end
