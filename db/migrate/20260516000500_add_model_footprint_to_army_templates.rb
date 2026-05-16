class AddModelFootprintToArmyTemplates < ActiveRecord::Migration[8.1]
  class MigrationArmyTemplate < ApplicationRecord
    self.table_name = :army_templates
  end

  def up
    add_column :army_templates, :model_class, :string, null: false, default: 'infantry'
    add_column :army_templates, :model_base_width, :integer
    add_column :army_templates, :model_base_depth, :integer

    MigrationArmyTemplate.reset_column_information

    MigrationArmyTemplate.find_each do |template|
      template.update_columns(model_class: infer_model_class(template))
    end
  end

  def down
    remove_column :army_templates, :model_base_depth
    remove_column :army_templates, :model_base_width
    remove_column :army_templates, :model_class
  end

  private

  def infer_model_class(template)
    abilities = Array(template.abilities)

    return 'machine' if abilities.include?('machine')
    return 'monster' if abilities.include?('monster')
    return 'cavalry' if template.mounted? || abilities.include?('charge') || abilities.include?('fast')

    'infantry'
  end
end