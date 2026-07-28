require "test_helper"

class SimBattleReplayTest < ActiveSupport::TestCase
  test "replay reproduces stored matchup result" do
    game = create_active_game(player_count: 2)
    result = Games::AdvanceRound.call(game: game, base_version: 0)
    assert result.ok?, result.error

    matchup = game.round_matchups.first
    assert matchup.completed?

    payload = Sim::Battle::Replay.call(matchup: matchup, compare: true)

    assert payload[:compare][:identical]
    assert_equal matchup.seed, payload[:seed]
    assert payload[:result][:rounds].any?
  end

  test "replay finds matchup from battle id" do
    game = create_active_game(player_count: 2)
    result = Games::AdvanceRound.call(game: game, base_version: 0)
    assert result.ok?, result.error

    battle = game.battles.first
    matchup = Sim::Battle::Replay.find_matchup!(battle: battle)
    assert_equal game.round_matchups.first.id, matchup.id
  end
end
