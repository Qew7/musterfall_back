class CreateRoundMatchups < ActiveRecord::Migration[8.1]
  def change
    create_table :round_matchups do |t|
      t.references :game, null: false, foreign_key: true
      t.integer :campaign_round, null: false
      t.integer :position, null: false
      t.string :attacker_player_key, null: false
      t.string :defender_player_key, null: false
      t.string :attacker_player_name, null: false
      t.string :defender_player_name, null: false
      t.bigint :seed, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :attacker_snapshot, null: false, default: {}
      t.jsonb :defender_snapshot, null: false, default: {}
      t.jsonb :result_payload, default: {}
      t.text :error_message
      t.timestamps
    end

    add_index :round_matchups, [ :game_id, :campaign_round, :position ], unique: true, name: "index_round_matchups_on_game_round_position"
    add_index :round_matchups, [ :game_id, :campaign_round, :status ], name: "index_round_matchups_on_game_round_status"
  end
end
