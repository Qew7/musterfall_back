class CreateGameCatalog < ActiveRecord::Migration[8.1]
  def change
    create_table :factions do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :vibe, null: false
      t.string :passive, null: false
      t.string :color, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :factions, :slug, unique: true
    add_index :factions, :position

    create_table :army_templates do |t|
      t.string :template_key, null: false
      t.string :kind, null: false
      t.references :faction, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :cost, null: false
      t.integer :models, null: false
      t.integer :model_health, null: false
      t.integer :width, null: false
      t.string :armor_type, null: false
      t.string :weapon_type, null: false
      t.integer :melee, null: false, default: 0
      t.integer :ranged, null: false, default: 0
      t.integer :spell, null: false, default: 0
      t.integer :initiative, null: false
      t.boolean :mounted, null: false, default: false
      t.jsonb :abilities, null: false, default: []

      t.timestamps
    end

    add_index :army_templates, :template_key, unique: true
    add_index :army_templates, [ :faction_id, :kind ]

    create_table :hero_upgrades do |t|
      t.string :upgrade_key, null: false
      t.string :name, null: false
      t.string :category, null: false
      t.string :summary, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :hero_upgrades, :upgrade_key, unique: true
    add_index :hero_upgrades, :position
  end
end
