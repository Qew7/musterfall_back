class AddSkillToArmyTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :army_templates, :skill, :integer, null: false, default: 3
  end
end
