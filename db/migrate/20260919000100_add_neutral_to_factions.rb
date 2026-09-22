class AddNeutralToFactions < ActiveRecord::Migration[8.0]
  def change
    add_column :factions, :neutral, :boolean, null: false, default: false
  end
end
