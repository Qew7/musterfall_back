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

  test "victory points use unit cost and ignore leftover routing hp" do
    left = {
      combatants: [
        { cost: 4, starting_models: 4, models_remaining: 4, current_health: 4, is_routing: false }
      ]
    }
    right = {
      combatants: [
        { cost: 20, starting_models: 1, models_remaining: 1, current_health: 20, is_routing: true }
      ]
    }

    assert_equal 20, Sim::Battle::State.victory_points(right)
    assert_equal 0, Sim::Battle::State.victory_points(left)
    assert_equal [ 20, 4 ], Sim::Battle::State.victory_score(left, right)
    assert_equal [ 0, 0 ], Sim::Battle::State.victory_score(right, left)
    assert_equal 1, Sim::Battle::State.victory_score(left, right) <=> Sim::Battle::State.victory_score(right, left)
  end

  test "half models remaining awards half cost" do
    broken = { cost: 10, starting_models: 10, models_remaining: 5, current_health: 5, is_routing: false }
    assert_equal 5, Sim::Battle::State.unit_bounty(broken)
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
