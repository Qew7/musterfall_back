require "test_helper"

class SimCampaignDismissTest < ActiveSupport::TestCase
  setup do
    @game = create_active_game
    assign_first_faction!(@game)
    @campaign = Sim::Persistence::CampaignRepository.new.load(@game.reload)
    player = @campaign.find_player("player-1")
    template = catalog.unit_templates(player[:faction_id]).first
    on_market!(player, template[:id])
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

  test "dismissing holdMarket unit holds the current shop" do
    player = @campaign.find_player("player-1")
    ogre = player[:roster].find { |entity| entity[:kind] == "unit" }
    ogre[:components][:abilities] = [ "holdMarket" ]
    player[:market_offer] = %w[frozen_offer]
    player[:hold_market] = false

    result = Sim::Campaign::Dismiss.call(campaign: @campaign, player_id: "player-1", entity_id: ogre[:id])
    assert result.ok?
    held = result.value.find_player("player-1")
    assert held[:hold_market]
    assert_equal %w[frozen_offer], held[:market_offer]
  end
end
