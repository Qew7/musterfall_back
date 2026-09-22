class AddMarketOfferToGamePlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :game_players, :market_offer, :jsonb, null: false, default: []
  end
end
