class AddRecruitStrategyToGamePlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :game_players, :recruit_strategy, :string
  end
end
