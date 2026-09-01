class CreateBalanceDuelMatrixRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :balance_duel_matrix_runs do |t|
      t.references :catalog_version, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.jsonb :config, null: false, default: {}
      t.jsonb :unit_templates, null: false, default: []
      t.integer :seed, null: false
      t.integer :batches_total, null: false, default: 0
      t.integer :batches_completed, null: false, default: 0
      t.integer :matchups_total, null: false, default: 0
      t.integer :matchups_completed, null: false, default: 0
      t.integer :matchups_failed, null: false, default: 0
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :balance_duel_matrix_runs, [ :status, :created_at ]
  end
end
