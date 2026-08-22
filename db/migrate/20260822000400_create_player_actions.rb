class CreatePlayerActions < ActiveRecord::Migration[8.1]
  def change
    create_table :player_actions do |t|
      t.references :game, foreign_key: true
      t.string :action, null: false
      t.integer :http_status, null: false
      t.string :player_id
      t.jsonb :params, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :player_actions, [ :game_id, :created_at ]
  end
end
