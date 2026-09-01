class CreateBalanceSimulationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :balance_simulation_runs do |t|
      t.references :catalog_version, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.jsonb :config, null: false, default: {}
      t.integer :battles_completed, null: false, default: 0
      t.integer :battles_failed, null: false, default: 0
      t.bigint :seed, null: false
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :balance_simulation_runs, [ :status, :created_at ]

    add_reference :balance_battle_rollups, :balance_simulation_run, foreign_key: true, null: true
  end
end
