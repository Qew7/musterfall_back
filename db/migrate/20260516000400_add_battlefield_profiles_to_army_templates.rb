class AddBattlefieldProfilesToArmyTemplates < ActiveRecord::Migration[8.1]
  def change
    change_table :army_templates, bulk: true do |t|
      t.integer :base_depth, null: false, default: 1
      t.integer :shooting_range, null: false, default: 0
      t.integer :spell_range, null: false, default: 0
      t.string :shooting_template, null: false, default: 'single'
      t.string :spell_template, null: false, default: 'single'
      t.boolean :requires_line_of_sight, null: false, default: true
    end
  end
end
