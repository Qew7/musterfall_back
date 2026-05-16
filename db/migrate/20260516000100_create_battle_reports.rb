class CreateBattleReports < ActiveRecord::Migration[8.1]
  def change
    create_table :battles do |t|
      t.references :game, null: false, foreign_key: true
      t.integer :round_number, null: false
      t.string :left_player_id, null: false
      t.string :left_player_name, null: false
      t.string :right_player_id, null: false
      t.string :right_player_name, null: false
      t.string :winner_id, null: false
      t.string :winner_name, null: false
      t.string :summary, null: false
      t.jsonb :left_payload, null: false, default: {}
      t.jsonb :right_payload, null: false, default: {}
      t.jsonb :events, null: false, default: []

      t.timestamps
    end

    add_index :battles, [ :game_id, :round_number, :left_player_id, :right_player_id ], unique: true, name: "index_battles_on_round_and_players"

    create_table :battle_rounds do |t|
      t.references :battle, null: false, foreign_key: true
      t.integer :number, null: false
      t.jsonb :events, null: false, default: []

      t.timestamps
    end

    add_index :battle_rounds, [ :battle_id, :number ], unique: true

    create_table :battle_turns do |t|
      t.references :battle_round, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :player_id, null: false
      t.string :player_name, null: false

      t.timestamps
    end

    add_index :battle_turns, [ :battle_round_id, :position ], unique: true

    create_table :battle_phases do |t|
      t.references :battle_turn, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :phase_type, null: false
      t.string :label, null: false
      t.jsonb :events, null: false, default: []

      t.timestamps
    end

    add_index :battle_phases, [ :battle_turn_id, :position ], unique: true
  end
end
