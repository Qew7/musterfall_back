require "test_helper"

class GamesApplyCommandTest < ActiveSupport::TestCase
  test "increments version on success" do
    game = create_active_game
    result = Games::ApplyCommand.call(
      game: game,
      command: :assign_faction,
      base_version: 0,
      params: {
        player_id: "player-1",
        faction_id: catalog.factions.first[:id],
        school_key: starter_school_key(catalog.factions.first[:id])
      }
    )

    assert result.ok?
    assert_equal 1, result.value[:campaign].version
    assert_equal 1, game.reload.campaign_version
  end

  test "version conflict returns conflict code" do
    game = create_active_game
    assign_first_faction!(game)
    result = Games::ApplyCommand.call(
      game: game.reload,
      command: :recruit,
      base_version: 0,
      params: {
        player_id: "player-1",
        template_id: catalog.unit_templates(catalog.factions.first[:id]).first[:id]
      }
    )

    assert result.failure?
    assert_equal :conflict, result.code
  end
end
