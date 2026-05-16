class AddAttacksToArmyTemplates < ActiveRecord::Migration[7.0]
  def change
    add_column :army_templates, :attacks, :integer, null: false, default: 1
  end
end
