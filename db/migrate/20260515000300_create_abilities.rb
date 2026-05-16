class CreateAbilities < ActiveRecord::Migration[8.1]
  def change
    create_table :abilities do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :category, null: false
      t.string :description, null: false

      t.timestamps
    end

    add_index :abilities, :key, unique: true

    create_table :army_template_abilities do |t|
      t.references :army_template, null: false, foreign_key: true
      t.references :ability, null: false, foreign_key: true

      t.timestamps
    end

    add_index :army_template_abilities, [:army_template_id, :ability_id], unique: true, name: "idx_template_abilities_unique"
  end
end