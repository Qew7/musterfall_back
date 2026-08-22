class RenameRecruitTiersToLineElite < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE army_templates SET recruit_tier = 'line' WHERE recruit_tier = 'common';
      UPDATE army_templates SET recruit_tier = 'elite' WHERE recruit_tier = 'special';
    SQL
    change_column_default :army_templates, :recruit_tier, from: "common", to: "line"
  end

  def down
    execute <<~SQL.squish
      UPDATE army_templates SET recruit_tier = 'common' WHERE recruit_tier = 'line';
      UPDATE army_templates SET recruit_tier = 'special' WHERE recruit_tier = 'elite';
    SQL
    change_column_default :army_templates, :recruit_tier, from: "line", to: "common"
  end
end
