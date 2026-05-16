class AddMovementToArmyTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :army_templates, :movement, :integer, null: false, default: 3
  end
end