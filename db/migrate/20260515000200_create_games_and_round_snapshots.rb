class CreateGamesAndRoundSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :games do |t|
      t.string :status, null: false, default: "draft"
      t.integer :player_count, null: false
      t.integer :current_round, null: false, default: 1
      t.jsonb :state_payload, null: false, default: {}

      t.timestamps
    end

    add_index :games, :status

    create_table :round_snapshots do |t|
      t.references :game, null: false, foreign_key: true
      t.integer :round_number, null: false
      t.string :phase, null: false
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :round_snapshots, [:game_id, :round_number, :phase], unique: true
  end
end