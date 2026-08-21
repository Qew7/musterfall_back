class AllowDuplicateBattlesForReplay < ActiveRecord::Migration[8.1]
  def change
    remove_index :battles, name: "index_battles_on_round_and_players"
    add_index :battles, [ :game_id, :round_number, :left_player_id, :right_player_id ],
              name: "index_battles_on_round_and_players"
  end
end
