require "test_helper"

class SimCampaignPrepareRoundTest < ActiveSupport::TestCase
  test "assigns missing factions and recruits for bots" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    result = Sim::Campaign::PrepareRound.call(
      campaign: campaign,
      catalog: catalog,
      rng: Sim::Rng::Seeded.new(5)
    )

    assert result.ok?
    human = result.value.find_player("player-1")
    bot = result.value.find_player("player-2")
    assert human[:faction_id].present?
    assert bot[:faction_id].present?
    assert bot[:roster].any? { |entity| entity[:kind] == "unit" }
  end
end
