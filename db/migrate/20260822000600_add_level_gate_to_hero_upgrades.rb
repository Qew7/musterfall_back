class AddLevelGateToHeroUpgrades < ActiveRecord::Migration[8.1]
  def change
    add_column :hero_upgrades, :min_level, :integer, null: false, default: 1
    add_column :hero_upgrades, :general_only, :boolean, null: false, default: false
  end
end
