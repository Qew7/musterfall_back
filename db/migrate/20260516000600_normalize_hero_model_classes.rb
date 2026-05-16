class NormalizeHeroModelClasses < ActiveRecord::Migration[8.1]
  class MigrationArmyTemplate < ApplicationRecord
    self.table_name = :army_templates
  end

  def up
    MigrationArmyTemplate.where(kind: 'hero').find_each do |template|
      template.update_columns(model_class: template.mounted? ? 'cavalry' : 'infantry')
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Hero model classes are normalized from current business rules only'
  end
end
