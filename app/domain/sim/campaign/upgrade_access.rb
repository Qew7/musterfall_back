module Sim
  module Campaign
    class UpgradeAccess
      def self.call(campaign:, player_id:)
        new(campaign, player_id).call
      end

      def initialize(campaign, player_id)
        @campaign = campaign.deep_dup
        @player_id = player_id
      end

      def call
        player = @campaign.find_player(@player_id)
        return Result.failure("player not found", code: :not_found) unless player
        return Result.failure("player is not active") unless player[:status] == "active"

        cost = RecruitAccess.upgrade_cost(player[:recruit_access].to_i)
        return Result.failure("recruit access already maxed") unless cost
        return Result.failure("insufficient treasury") if player[:treasury] < cost

        player[:treasury] -= cost
        player[:recruit_access] = player[:recruit_access].to_i + 1
        slots = RecruitAccess.slots_for(player[:recruit_access])
        player[:round_notes] = [
          "Доступ найма #{player[:recruit_access]}: герои #{slots[:hero]}, elite #{slots[:elite]}, rare #{slots[:rare]} (−#{cost})"
        ]
        Result.ok(@campaign)
      end
    end
  end
end
