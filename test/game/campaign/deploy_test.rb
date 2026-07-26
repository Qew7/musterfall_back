require "test_helper"

class SimCampaignDeployTest < ActiveSupport::TestCase
  setup do
    @game = create_active_game
    assign_first_faction!(@game)
    @campaign = Sim::Persistence::CampaignRepository.new.load(@game.reload)
    @hero_id = @campaign.find_player("player-1")[:roster].first[:id]
  end

  test "auto deploy places living entities out of reserve" do
    result = Sim::Campaign::Deploy.call(campaign: @campaign, player_id: "player-1", action: "auto")
    assert result.ok?
    hero = result.value.find_entity("player-1", @hero_id)
    assert_not_equal "reserve", hero.dig(:components, :formation, :row)
  end

  test "transform rejects attached hero placement" do
    template = catalog.unit_templates(@campaign.find_player("player-1")[:faction_id]).first
    @campaign = Sim::Campaign::Recruit.call(
      campaign: @campaign,
      catalog: catalog,
      player_id: "player-1",
      template_id: template[:id]
    ).value
    unit_id = @campaign.find_player("player-1")[:roster].find { |entity| entity[:kind] == "unit" }[:id]
    @campaign = Sim::Campaign::AttachHero.call(
      campaign: @campaign,
      player_id: "player-1",
      hero_id: @hero_id,
      unit_id: unit_id
    ).value

    result = Sim::Campaign::Deploy.call(
      campaign: @campaign,
      player_id: "player-1",
      action: "transform",
      entity_id: @hero_id,
      x: 3,
      y: 10
    )

    assert result.failure?
  end

  test "unknown action fails" do
    result = Sim::Campaign::Deploy.call(campaign: @campaign, player_id: "player-1", action: "teleport")
    assert result.failure?
  end
end
