class CreateBalanceAuditTables < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_versions do |t|
      t.string :content_hash, null: false
      t.string :catalog_hash, null: false
      t.string :rules_hash, null: false
      t.timestamps
    end
    add_index :catalog_versions, :content_hash, unique: true

    create_table :balance_battle_rollups do |t|
      t.references :catalog_version, null: false, foreign_key: true
      t.references :round_matchup, null: true, foreign_key: true, index: false
      t.references :game, null: true, foreign_key: true
      t.string :matchup_type, null: false
      t.string :source, null: false, default: "campaign"
      t.jsonb :metrics, null: false, default: {}
      t.timestamps
    end
    add_index :balance_battle_rollups, [ :catalog_version_id, :created_at ]
    add_index :balance_battle_rollups, :round_matchup_id, unique: true, where: "round_matchup_id IS NOT NULL"

    create_table :balance_counters do |t|
      t.references :catalog_version, null: false, foreign_key: true
      t.string :bucket, null: false
      t.string :key, null: false
      t.string :matchup_type, null: false, default: "all"
      t.bigint :n, null: false, default: 0
      t.bigint :sum, null: false, default: 0
      t.timestamps
    end
    add_index :balance_counters,
      [ :catalog_version_id, :bucket, :key, :matchup_type ],
      unique: true,
      name: "index_balance_counters_unique"
  end
end
