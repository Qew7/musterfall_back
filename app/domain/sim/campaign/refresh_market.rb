module Sim
  module Campaign
    class RefreshMarket
      def self.call(campaign:, catalog:, player_id:, rng:)
        new(campaign, catalog, player_id, rng).call
      end

      def initialize(campaign, catalog, player_id, rng)
        @campaign = campaign.deep_dup
        @catalog = catalog
        @player_id = player_id
        @rng = rng
      end

      def call
        player = @campaign.find_player(@player_id)
        return Result.failure("player not found", code: :not_found) unless player
        return Result.failure("player is not active") unless player[:status] == "active"
        return Result.failure("faction required") if player[:faction_id].blank?
        cost = RecruitAccess.refresh_cost(player)
        return Result.failure("insufficient treasury") unless RecruitAccess.refresh_offer!(player, @catalog, @rng)

        player[:round_notes] = [ "Новый набор (−#{cost})" ]
        Result.ok(@campaign)
      end
    end
  end
end
