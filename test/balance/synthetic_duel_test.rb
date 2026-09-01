require "test_helper"

class BalanceSyntheticDuelTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    @catalog = Sim::Catalog::Loader.load
    @rng = Sim::Rng::Seeded.new(42_002)
  end

  test "duel runs without writing battle audit rows" do
    before_rollups = BalanceBattleRollup.count
    before_duels = BalanceDuelRun.count

    result = Balance::Synthetic::Duel.run!(
      catalog: @catalog,
      config: {
        left_template: "state_swords",
        right_template: "rift_heavies",
        contact: "front",
        iterations: 3
      },
      rng: @rng
    )

    assert_equal 3, result[:iterations]
    assert_equal 3, result[:left_wins] + result[:right_wins]
    assert_operator result[:avg_rounds], :>, 0
    assert_equal before_rollups, BalanceBattleRollup.count
    assert_equal before_duels, BalanceDuelRun.count
  end

  test "persist writes duel run for catalog version" do
    result = Balance::Synthetic::Duel.run!(
      catalog: @catalog,
      config: {
        left_template: "state_swords",
        right_template: "rift_heavies",
        contact: "front",
        iterations: 3
      },
      rng: @rng
    )

    run = Balance::Duel::Persist.call!(
      result: result,
      config: { left_template: "state_swords", right_template: "rift_heavies", contact: "front", iterations: 3 },
      catalog_version: CatalogVersion.current!
    )

    assert_equal "state_swords", run.left_template
    assert_equal 3, run.iterations
  end

  test "ranged deploy uses wider standoff than melee when shooter involved" do
    factory = Sim::Entities::Factory.new(@catalog, id_sequence: { value: 0 })
    left = factory.create_unit("handgunners", "left")
    right = factory.create_unit("state_swords", "right")
    Sim::Entities::Footprint.sync_entity!(left)
    Sim::Entities::Footprint.sync_entity!(right)

    melee_gap = Balance::Synthetic::Duel.engagement_gap(left, right, deploy: "melee")
    ranged_gap = Balance::Synthetic::Duel.engagement_gap(left, right, deploy: "ranged")

    assert_operator ranged_gap, :>, melee_gap
    assert_operator ranged_gap, :>=, left.dig(:components, :combat, :shooting_range).to_i
  end

  test "ranged deploy keeps pure melee pairs at standoff not contact" do
    factory = Sim::Entities::Factory.new(@catalog, id_sequence: { value: 0 })
    left = factory.create_unit("state_swords", "left")
    right = factory.create_unit("orc_brutes", "right")
    Sim::Entities::Footprint.sync_entity!(left)
    Sim::Entities::Footprint.sync_entity!(right)

    melee_gap = Balance::Synthetic::Duel.engagement_gap(left, right, deploy: "melee")
    ranged_gap = Balance::Synthetic::Duel.engagement_gap(left, right, deploy: "ranged")

    assert_operator ranged_gap, :>, melee_gap
    assert_in_delta Balance::Synthetic::Duel::STANDOFF_GAP, ranged_gap, 0.001
  end

  test "run result includes deploy mode" do
    result = Balance::Synthetic::Duel.run!(
      catalog: @catalog,
      config: {
        left_template: "handgunners",
        right_template: "state_swords",
        contact: "front",
        deploy: "ranged",
        iterations: 1
      },
      rng: @rng
    )

    assert_equal "ranged", result[:deploy]
  end

  test "random_first_turn swaps simulator player order" do
    order = 5.times.map do
      rng = Sim::Rng::Seeded.new(rand(0x7FFFFFFF))
      left = { id: "duel-left" }
      right = { id: "duel-right" }
      first, = Balance::Synthetic::Duel.pick_turn_order(left, right, rng: rng, randomize: true)
      first[:id]
    end

    assert_includes order, "duel-left"
    assert_includes order, "duel-right"
  end
end
