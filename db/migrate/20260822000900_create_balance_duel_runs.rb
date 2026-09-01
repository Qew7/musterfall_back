class CreateBalanceDuelRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :balance_duel_runs do |t|
      t.references :catalog_version, null: false, foreign_key: true
      t.string :left_template, null: false
      t.string :right_template, null: false
      t.string :contact, null: false, default: "front"
      t.integer :iterations, null: false
      t.integer :left_models
      t.integer :right_models
      t.integer :left_wins, null: false, default: 0
      t.integer :right_wins, null: false, default: 0
      t.decimal :left_winrate, null: false, default: 0, precision: 8, scale: 4
      t.decimal :right_winrate, null: false, default: 0, precision: 8, scale: 4
      t.decimal :avg_rounds, null: false, default: 0, precision: 8, scale: 2
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end

    add_index :balance_duel_runs, [ :catalog_version_id, :created_at ]
    add_index :balance_duel_runs,
      [ :catalog_version_id, :left_template, :right_template, :contact ],
      name: "index_balance_duel_runs_on_matchup"
  end
end
