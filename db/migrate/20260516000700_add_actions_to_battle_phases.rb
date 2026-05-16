class AddActionsToBattlePhases < ActiveRecord::Migration[8.1]
  def change
    add_column :battle_phases, :actions, :jsonb, default: [], null: false
  end
end