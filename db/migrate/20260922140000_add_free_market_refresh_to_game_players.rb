class AddFreeMarketRefreshToGamePlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :game_players, :free_market_refresh, :boolean, null: false, default: false
  end
end
