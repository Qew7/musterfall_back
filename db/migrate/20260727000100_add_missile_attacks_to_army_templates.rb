class AddMissileAttacksToArmyTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :army_templates, :missile_attacks, :integer, null: false, default: 1
  end
end
