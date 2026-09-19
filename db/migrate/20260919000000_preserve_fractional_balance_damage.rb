class PreserveFractionalBalanceDamage < ActiveRecord::Migration[8.0]
  def up
    change_column :balance_counters, :sum, :float, default: 0, null: false
  end

  def down
    change_column :balance_counters, :sum, :bigint, default: 0, null: false
  end
end
