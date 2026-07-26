require "test_helper"

class SimCampaignRepositoryTest < ActiveSupport::TestCase
  test "replace and load round-trips roster and attachments" do
    game = create_active_game
    assign_first_faction!(game)
    template = catalog.unit_templates(catalog.factions.first[:id]).first
    Games::ApplyCommand.call(
      game: game.reload,
      command: :recruit,
      base_version: game.campaign_version,
      params: { player_id: "player-1", template_id: template[:id] }
    )
    campaign = Sim::Persistence::CampaignRepository.new.load(game.reload)
    hero = campaign.find_player("player-1")[:roster].find { |entity| entity[:kind] == "hero" }
    unit = campaign.find_player("player-1")[:roster].find { |entity| entity[:kind] == "unit" }
    campaign = Sim::Campaign::AttachHero.call(
      campaign: campaign,
      player_id: "player-1",
      hero_id: hero[:id],
      unit_id: unit[:id]
    ).value
    campaign.version = game.campaign_version + 1
    Sim::Persistence::CampaignRepository.new.replace!(game, campaign)

    reloaded = Sim::Persistence::CampaignRepository.new.load(game.reload)
    attached = reloaded.find_entity("player-1", hero[:id])
    assert_equal unit[:id], attached[:state][:attached_to]
    assert_includes reloaded.find_entity("player-1", unit[:id])[:state][:attached_hero_ids], hero[:id]
  end
end
