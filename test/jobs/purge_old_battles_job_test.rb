require "test_helper"

class PurgeOldBattlesJobTest < ActiveJob::TestCase
  setup do
    @game = Game.create!(player_count: 2)
  end

  test "deletes battles three weeks old or older and keeps newer ones" do
    freeze_time do
      old = insert_battle(created_at: 3.weeks.ago)
      keep = insert_battle(created_at: 3.weeks.ago + 1.second)

      PurgeOldBattlesJob.perform_now

      refute Battle.exists?(old.id)
      assert Battle.exists?(keep.id)
    end
  end

  def insert_battle(created_at:)
    battle = @game.battles.create!(
      round_number: 1,
      left_player_id: "player-1",
      left_player_name: "A",
      right_player_id: "player-2",
      right_player_name: "B",
      winner_id: "player-1",
      winner_name: "A",
      summary: "win"
    )
    battle.update_columns(created_at: created_at)
    battle
  end
end
