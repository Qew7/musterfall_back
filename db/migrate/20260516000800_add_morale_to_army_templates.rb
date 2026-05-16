class AddMoraleToArmyTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :army_templates, :morale, :integer, null: false, default: 5
  end
end
