module Sim
  module Campaign
    class Dismiss
      def self.call(campaign:, player_id:, entity_id:)
        new(campaign, player_id, entity_id).call
      end

      def initialize(campaign, player_id, entity_id)
        @campaign = campaign.deep_dup
        @player_id = player_id
        @entity_id = entity_id
      end

      def call
        player = @campaign.find_player(@player_id)
        entity = player&.dig(:roster)&.find { |entry| entry[:id] == @entity_id }
        return Result.failure("entity not found", code: :not_found) unless player && entity
        return Result.failure("cannot dismiss free starter hero") if entity[:kind] == "hero" && entity.dig(:components, :economy, :cost).to_i.zero?

        refund = [ 1, (entity.dig(:components, :economy, :cost).to_i / 2) ].max
        player[:treasury] += refund
        player[:roster] = player[:roster].reject { |entry| entry[:id] == @entity_id }
        player[:roster].each do |entry|
          if entry[:kind] == "unit"
            entry[:state][:attached_hero_ids] = Array(entry[:state][:attached_hero_ids]).reject { |id| id == @entity_id }
          elsif entry[:kind] == "hero" && entry[:state][:attached_to] == @entity_id
            entry[:state][:attached_to] = nil
            entry[:state][:attached_slot] = nil
          end
        end

        Result.ok(@campaign)
      end
    end
  end
end
