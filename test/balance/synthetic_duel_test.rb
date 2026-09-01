require "test_helper"

class BalanceSyntheticDuelTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    @catalog = Sim::Catalog::Loader.load
    @rng = Sim::Rng::Seeded.new(42_002)
  end

  test "duel runs without writing audit rows" do
    before = BalanceBattleRollup.count

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
    assert_equal before, BalanceBattleRollup.count
  end
end
