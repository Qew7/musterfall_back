class AddFactionAndRepeatableToHeroUpgrades < ActiveRecord::Migration[8.1]
  def change
    add_reference :hero_upgrades, :faction, foreign_key: true
    add_column :hero_upgrades, :repeatable, :boolean, null: false, default: false
  end
end
