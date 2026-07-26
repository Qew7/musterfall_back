class NormalizeCampaignState < ActiveRecord::Migration[8.1]
  def change
    change_table :games, bulk: true do |t|
      t.integer :campaign_version, null: false, default: 0
      t.string :winner_player_key
      t.jsonb :last_round_report
      t.bigint :rng_seed, null: false, default: 0
    end

    create_table :game_players do |t|
      t.references :game, null: false, foreign_key: true
      t.string :external_key, null: false
      t.string :name, null: false
      t.boolean :is_bot, null: false, default: false
      t.string :status, null: false, default: "active"
      t.string :faction_key
      t.integer :treasury, null: false, default: 36
      t.integer :victories, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.jsonb :round_notes, null: false, default: []
      t.timestamps
    end

    add_index :game_players, [ :game_id, :external_key ], unique: true
    add_index :game_players, [ :game_id, :position ]

    create_table :game_entities do |t|
      t.references :game_player, null: false, foreign_key: true
      t.string :external_key, null: false
      t.string :kind, null: false
      t.string :template_key, null: false
      t.string :name, null: false
      t.integer :current_health, null: false
      t.boolean :is_routing, null: false, default: false
      t.string :row_key, null: false, default: "reserve"
      t.string :lane_key, null: false, default: "center"
      t.float :x, null: false, default: 0
      t.float :y, null: false, default: 0
      t.float :facing, null: false, default: 0
      t.jsonb :formation, null: false, default: {}
      t.jsonb :combat, null: false, default: {}
      t.jsonb :abilities, null: false, default: []
      t.jsonb :health, null: false, default: {}
      t.jsonb :economy, null: false, default: {}
      t.jsonb :progression, null: false, default: {}
      t.jsonb :hero, null: false, default: {}
      t.jsonb :identity, null: false, default: {}
      t.timestamps
    end

    add_index :game_entities, [ :game_player_id, :external_key ], unique: true
    add_index :game_entities, :kind

    create_table :game_entity_attachments do |t|
      t.references :hero_entity, null: false, foreign_key: { to_table: :game_entities }, index: { unique: true }
      t.references :unit_entity, null: false, foreign_key: { to_table: :game_entities }
      t.string :slot, null: false
      t.timestamps
    end

    add_index :game_entity_attachments, [ :unit_entity_id, :slot ], unique: true
  end
end
