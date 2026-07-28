require "test_helper"

class Api::BattlesReplayTest < ActionDispatch::IntegrationTest
  test "replays stored matchup with same seed without changing db" do
    game = create_active_game(player_count: 2)
    result = Games::AdvanceRound.call(game: game, base_version: 0)
    assert result.ok?, result.error

    matchup = game.round_matchups.first
    stored_payload = matchup.result_payload.deep_dup

    post "/api/games/#{game.id}/battles/replay", params: {
      matchup_id: matchup.id
    }

    assert_response :success
    body = response.parsed_body
    battle = body.fetch("battle")
    assert_equal matchup.seed, battle.fetch("seed")
    assert_equal matchup.id, battle.fetch("matchupId")
    assert battle.fetch("winnerId").present?

    matchup.reload
    assert_equal stored_payload, matchup.result_payload
  end

  test "replays by round and player ids" do
    game = create_active_game(player_count: 2)
    result = Games::AdvanceRound.call(game: game, base_version: 0)
    assert result.ok?, result.error

    battle = game.battles.first
    post "/api/games/#{game.id}/battles/replay", params: {
      round_number: battle.round_number,
      left_player_id: battle.left_player_id,
      right_player_id: battle.right_player_id
    }

    assert_response :success
    assert response.parsed_body.dig("battle", "summary").present?
  end
end
