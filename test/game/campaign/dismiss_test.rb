require "test_helper"

class SimCampaignDismissTest < ActiveSupport::TestCase
  setup do
    @game = create_active_game
    assign_first_faction!(@game)
    @campaign = Sim::Persistence::CampaignRepository.new.load(@game.reload)
    template = catalog.unit_templates(@campaign.find_player("player-1")[:faction_id]).first
    @campaign = Sim::Campaign::Recruit.call(
      campaign: @campaign,
      catalog: catalog,
      player_id: "player-1",
      template_id: template[:id]
    ).value
    @entity_id = @campaign.find_player("player-1")[:roster].find { |entity| entity[:kind] == "unit" }[:id]
  end

  test "dismiss refunds half cost" do
    before = @campaign.find_player("player-1")[:treasury]
    entity = @campaign.find_entity("player-1", @entity_id)
    result = Sim::Campaign::Dismiss.call(campaign: @campaign, player_id: "player-1", entity_id: @entity_id)

    assert result.ok?
    expected = before + [ 1, entity.dig(:components, :economy, :cost) / 2 ].max
    assert_equal expected, result.value.find_player("player-1")[:treasury]
    assert_nil result.value.find_entity("player-1", @entity_id)
  end

  test "cannot dismiss free starter hero" do
    hero = @campaign.find_player("player-1")[:roster].find { |entity| entity[:kind] == "hero" }
    result = Sim::Campaign::Dismiss.call(campaign: @campaign, player_id: "player-1", entity_id: hero[:id])

    assert result.failure?
  end
end
