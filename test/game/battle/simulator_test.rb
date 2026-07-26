require "test_helper"

class SimBattleSimulatorTest < ActiveSupport::TestCase
  setup do
    game = create_active_game(player_count: 2)
    assign_first_faction!(game, player_id: "player-1")
    assign_first_faction!(game.reload, player_id: "player-2")
    Games::ApplyCommand.call(
      game: game.reload,
      command: :recruit,
      base_version: game.campaign_version,
      params: {
        player_id: "player-1",
        template_id: catalog.unit_templates(catalog.factions.first[:id]).first[:id]
      }
    )
    Games::ApplyCommand.call(
      game: game.reload,
      command: :deploy,
      base_version: game.reload.campaign_version,
      params: { player_id: "player-1", deploy_mode: "auto" }
    )
    Games::ApplyCommand.call(
      game: game.reload,
      command: :deploy,
      base_version: game.reload.campaign_version,
      params: { player_id: "player-2", deploy_mode: "auto" }
    )
    @campaign = Sim::Persistence::CampaignRepository.new.load(game.reload)
  end

  test "simulate battle returns winner phases and syncs health" do
    left = @campaign.find_player("player-1")
    right = @campaign.find_player("player-2")
    report = Sim::Battle::Simulator.call(left, right, catalog, rng: Sim::Rng::Seeded.new(11))

    assert report[:winner_id].present?
    assert report[:rounds].any?
    assert report[:left][:combatants]
    assert report[:right][:combatants]
    assert report[:summary].include?("vs")
  end
end
