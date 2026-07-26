module Games
  class CreateGame
    def self.call(player_count:)
      new(player_count).call
    end

    def initialize(player_count)
      @player_count = player_count
    end

    def call
      result = Sim::Campaign::Create.call(player_count: @player_count)
      return result if result.failure?

      campaign = result.value
      game = nil
      ActiveRecord::Base.transaction do
        game = Game.create!(
          player_count: @player_count,
          current_round: campaign.round,
          status: "active",
          campaign_version: 0,
          rng_seed: SecureRandom.random_number(1 << 31),
          state_payload: {}
        )
        Sim::Persistence::CampaignRepository.new.replace!(game, campaign)
      end

      Sim::Result.ok(game.reload)
    end
  end
end
