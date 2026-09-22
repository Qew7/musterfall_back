class AddHoldMarketToGamePlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :game_players, :hold_market, :boolean, default: false, null: false
  end
end
