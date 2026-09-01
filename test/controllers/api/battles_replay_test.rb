require "test_helper"

class Api::BattlesReplayTest < ActionDispatch::IntegrationTest
  test "replays stored matchup with same seed without changing db" do
    game = create_active_game(player_count: 2)
    result = Games::AdvanceRound.call(game: game, base_version: 0)
    assert result.ok?, result.error

    matchup = game.round_matchups.first
    stored_payload = matchup.result_payload.deep_dup
    original_ids = game.battles.order(:id).pluck(:id)

    post "/api/games/#{game.id}/battles/replay", params: {
      matchup_id: matchup.id
    }

    assert_response :success
    body = response.parsed_body
    battle = body.fetch("battle")
    battles = body.fetch("battles")
    assert_equal 1, battles.size
    assert_equal matchup.seed, battle.fetch("seed")
    assert_equal matchup.id, battle.fetch("matchupId")
    assert battle.fetch("winnerId").present?
    assert battle.fetch("battleId").to_i > original_ids.max.to_i

    matchup.reload
    assert_equal stored_payload, matchup.result_payload
    assert_equal original_ids, game.battles.where(id: original_ids).order(:id).pluck(:id)
    assert_equal original_ids.size + battles.size, game.battles.count
  end

  test "replays every matchup of the round as new battle rows" do
    game = create_active_game(player_count: 4)
    result = Games::AdvanceRound.call(game: game, base_version: 0)
    assert result.ok?, result.error

    matchups = game.round_matchups.order(:position)
    assert_operator matchups.size, :>, 1
    stored = matchups.map { |row| [ row.id, row.result_payload.deep_dup ] }
    original_ids = game.battles.order(:id).pluck(:id)

    post "/api/games/#{game.id}/battles/replay", params: {
      matchup_id: matchups.first.id
    }

    assert_response :success
    battles = response.parsed_body.fetch("battles")
    assert_equal matchups.size, battles.size
    assert_equal matchups.map(&:id), battles.map { |row| row.fetch("matchupId") }

    stored.each do |id, payload|
      assert_equal payload, RoundMatchup.find(id).result_payload
    end
    assert_equal original_ids, game.battles.where(id: original_ids).order(:id).pluck(:id)
    assert_equal original_ids.size + matchups.size, game.battles.count
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
