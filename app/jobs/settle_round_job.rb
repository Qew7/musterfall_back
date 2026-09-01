class SettleRoundJob < ApplicationJob
  queue_as :battles

  def perform(game_id, campaign_round)
    Game.transaction do
      game = Game.lock.find(game_id)
      Games::SettleRound.call(game: game, campaign_round: campaign_round)
    end
  end
end
