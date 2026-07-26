require "test_helper"

class GamesAdvanceRoundServiceTest < ActiveSupport::TestCase
  test "persists battles and snapshots" do
    game = create_active_game
    result = Games::AdvanceRound.call(game: game, base_version: 0)

    assert result.ok?
    game.reload
    assert game.battles.any?
    assert_equal %w[pre_round post_round].sort, game.round_snapshots.map(&:phase).sort
    assert_equal "finished", game.status
  end

  test "conflict when base version mismatches" do
    game = create_active_game
    assign_first_faction!(game)
    result = Games::AdvanceRound.call(game: game.reload, base_version: 0)

    assert result.failure?
    assert_equal :conflict, result.code
  end
end
