require "test_helper"

class SimCampaignAdvanceRoundTest < ActiveSupport::TestCase
  test "keeps loser active and advances round without crowning after first battle" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    prepared = Sim::Campaign::PrepareRound.call(
      campaign: campaign,
      catalog: catalog,
      rng: Sim::Rng::Seeded.new(8)
    ).value
    result = Sim::Campaign::AdvanceRound.call(
      campaign: prepared,
      catalog: catalog,
      rng: Sim::Rng::Seeded.new(8)
    )

    assert result.ok?
    payload = result.value
    assert_equal 1, payload[:battles].size
    assert_nil payload[:campaign].winner_id
    assert_equal 2, payload[:campaign].round
    assert_equal 2, payload[:campaign].players.count { |player| player[:status] == "active" }
    assert_nil payload[:meta_reward]
  end

  test "replaces leftover treasury with next round income" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    prepared = Sim::Campaign::PrepareRound.call(
      campaign: campaign,
      catalog: catalog,
      rng: Sim::Rng::Seeded.new(8)
    ).value
    prepared.players.each { |player| player[:treasury] = 999 }

    result = Sim::Campaign::AdvanceRound.call(
      campaign: prepared,
      catalog: catalog,
      rng: Sim::Rng::Seeded.new(8)
    )

    assert result.ok?
    expected = Sim::Constants.income_for(2)
    result.value[:campaign].players.select { |player| player[:status] == "active" }.each do |player|
      assert_equal expected, player[:treasury]
    end
  end
end
