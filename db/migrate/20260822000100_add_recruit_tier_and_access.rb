class AddRecruitTierAndAccess < ActiveRecord::Migration[8.1]
  def change
    add_column :army_templates, :recruit_tier, :string, null: false, default: "line"
    add_column :game_players, :recruit_access, :integer, null: false, default: 0
    change_column_default :game_players, :treasury, from: 36, to: 250
  end
end
