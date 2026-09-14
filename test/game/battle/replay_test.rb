require "test_helper"

class SimBattleReplayTest < ActiveSupport::TestCase
  test "replay reproduces stored matchup result" do
    game = create_active_game(player_count: 2)
    result = Games::AdvanceRound.call(game: game, base_version: 0)
    assert result.ok?, result.error

    matchup = game.round_matchups.first
    assert matchup.completed?

    payload = Sim::Battle::Replay.call(matchup: matchup, compare: :semantic)

    assert payload[:compare][:semantic_identical]
    assert_equal matchup.seed, payload[:seed]
    assert payload[:result][:rounds].any?
  end

  test "movement diff sees string-typed movement actions" do
    stored = {
      rounds: [ { turns: [ { phases: [ { actions: [
        { type: "movement", actor_id: "u1", from: { x: 1, y: 1, facing: 0 }, to: { x: 2, y: 1, facing: 0 } }
      ] } ] } ] } ]
    }
    fresh = {
      rounds: [ { turns: [ { phases: [ { actions: [
        { type: "movement", actor_id: "u1", from: { x: 1, y: 1, facing: 0 }, to: { x: 3, y: 1, facing: 0 } }
      ] } ] } ] } ]
    }
    replay = Sim::Battle::Replay.new(nil)
    diff = replay.send(:diff_movement_actions, stored, fresh)

    assert_equal 1, diff[:stored_count]
    assert_equal 1, diff[:fresh_count]
    assert diff[:changed]
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
