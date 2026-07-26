module Sim
  module Campaign
    class Deploy
      def self.call(campaign:, player_id:, action:, **args)
        new(campaign, player_id, action, args).call
      end

      def initialize(campaign, player_id, action, args)
        @campaign = campaign.deep_dup
        @player_id = player_id
        @action = action.to_s
        @args = args
      end

      def call
        player = @campaign.find_player(@player_id)
        return Result.failure("player not found", code: :not_found) unless player

        case @action
        when "transform" then transform!(player)
        when "rotate" then rotate!(player)
        when "reserve" then toggle_reserve!(player)
        when "auto" then auto_deploy!(player)
        else
          Result.failure("unknown deploy action")
        end
      end

      private

      def transform!(player)
        entity = player[:roster].find { |entry| entry[:id] == @args[:entity_id] }
        return Result.failure("entity not found", code: :not_found) unless entity
        return Result.failure("attached hero cannot be placed independently") if entity[:kind] == "hero" && entity[:state][:attached_to]

        position = Geometry::Battlefield.clamp_deployment_position(
          x: @args[:x],
          y: @args[:y],
          facing: @args[:facing] || entity.dig(:components, :formation, :facing)
        )
        formation = entity[:components][:formation]
        formation[:x] = position[:x]
        formation[:y] = position[:y]
        formation[:facing] = position[:facing]
        slots = Geometry::Battlefield.sync_formation_slots_from_deployment(position)
        formation[:lane] = slots[:lane]
        formation[:row] = slots[:row]
        Result.ok(@campaign)
      end

      def rotate!(player)
        entity = player[:roster].find { |entry| entry[:id] == @args[:entity_id] }
        return Result.failure("entity not found", code: :not_found) unless entity

        delta = @args[:direction].to_s == "left" ? -45 : 45
        entity[:components][:formation][:facing] = Geometry::Battlefield.rotate_facing(entity[:components][:formation][:facing], delta)
        Result.ok(@campaign)
      end

      def toggle_reserve!(player)
        entity = player[:roster].find { |entry| entry[:id] == @args[:entity_id] }
        return Result.failure("entity not found", code: :not_found) unless entity

        formation = entity[:components][:formation]
        if formation[:row] == "reserve"
          apply_formation_slot!(entity, "rear", formation[:lane])
        else
          apply_formation_slot!(entity, "reserve", formation[:lane])
        end
        Result.ok(@campaign)
      end

      def auto_deploy!(player)
        living = player[:roster].select { |entry| entry.dig(:state, :current_health).to_i > 0 }
        living.each_with_index do |entity, index|
          next if entity[:kind] == "hero" && entity[:state][:attached_to]

          row = Constants::BATTLE_ROWS[[ 2, index / 3 ].min]
          lane = Constants::LANE_ORDER[index % Constants::LANE_ORDER.length]
          apply_formation_slot!(entity, row, lane)
          position = Geometry::Battlefield.default_deployment(row, lane)
          entity[:components][:formation][:facing] = position[:facing]
        end
        Result.ok(@campaign)
      end

      def apply_formation_slot!(entity, row, lane)
        position = Geometry::Battlefield.default_deployment(row, lane)
        formation = entity[:components][:formation]
        formation[:row] = row
        formation[:lane] = lane
        formation[:x] = position[:x]
        formation[:y] = position[:y]
      end
    end
  end
end
