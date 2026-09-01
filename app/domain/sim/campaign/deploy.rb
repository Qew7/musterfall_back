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
        clash = placement_clash(entity, position, player[:roster])
        return Result.failure(clash) if clash

        apply_position!(entity, position)
        Result.ok(@campaign)
      end

      def rotate!(player)
        entity = player[:roster].find { |entry| entry[:id] == @args[:entity_id] }
        return Result.failure("entity not found", code: :not_found) unless entity

        formation = entity[:components][:formation]
        delta = @args[:direction].to_s == "left" ? -45 : 45
        facing = Geometry::Battlefield.rotate_facing(formation[:facing], delta)
        position = { x: formation[:x], y: formation[:y], facing: facing }
        clash = placement_clash(entity, position, player[:roster])
        return Result.failure(clash) if clash

        formation[:facing] = facing
        Result.ok(@campaign)
      end

      def toggle_reserve!(player)
        entity = player[:roster].find { |entry| entry[:id] == @args[:entity_id] }
        return Result.failure("entity not found", code: :not_found) unless entity

        formation = entity[:components][:formation]
        if formation[:row] == "reserve"
          return Result.failure("no clear deployment slot") unless place_in_slot!(entity, "rear", formation[:lane], player[:roster])
        else
          apply_formation_slot!(entity, "reserve", formation[:lane])
        end
        Result.ok(@campaign)
      end

      def auto_deploy!(player)
        deployable_entities(player).each_with_index do |entity, index|
          row = Constants::BATTLE_ROWS[[ 2, index / 3 ].min]
          lane = Constants::LANE_ORDER[index % Constants::LANE_ORDER.length]
          place_in_slot!(entity, row, lane, player[:roster])
        end
        Result.ok(@campaign)
      end

      def deployable_entities(player)
        player[:roster]
          .select { |entry| entry.dig(:state, :current_health).to_i > 0 }
          .reject { |entry| entry[:kind] == "hero" && entry[:state][:attached_to] }
          .sort_by { |entity| auto_deploy_sort_key(entity) }
      end

      def auto_deploy_sort_key(entity)
        Entities::Footprint.sync_entity!(entity)
        formation = entity[:components][:formation]
        area = -(formation[:width].to_f * formation[:depth].to_f)

        if entity[:kind] == "hero"
          return [ 0, 0, area ] if entity.dig(:components, :hero, :general)

          return [ 1, 0, area ]
        end

        [ 2, 0, area ]
      end

      def place_in_slot!(entity, row, lane, roster)
        clear = Geometry::Deployment.find_clear_position(entity, row, lane, roster, ignore_id: entity[:id])
        return false unless clear

        entity[:components][:formation][:facing] = clear[:facing] if clear[:facing]
        apply_position!(entity, clear)
        true
      end

      def apply_formation_slot!(entity, row, lane)
        position = Geometry::Battlefield.default_deployment(row, lane)
        formation = entity[:components][:formation]
        formation[:row] = row
        formation[:lane] = lane
        formation[:x] = position[:x]
        formation[:y] = position[:y]
      end

      def apply_position!(entity, position)
        formation = entity[:components][:formation]
        formation[:x] = position[:x]
        formation[:y] = position[:y]
        formation[:facing] = position[:facing] if position[:facing]
        slots = Geometry::Battlefield.sync_formation_slots_from_deployment(formation)
        formation[:lane] = slots[:lane]
        formation[:row] = slots[:row]
      end

      def placement_clash(entity, position, roster)
        # Reserve is a packing strip; only enforce separation inside battle rows.
        slots = Geometry::Battlefield.sync_formation_slots_from_deployment(position)
        return nil if slots[:row] == "reserve"

        conflicts = Geometry::Deployment.conflicting_entities(
          Geometry::Deployment.footprint_from_entity(entity, x: position[:x], y: position[:y], facing: position[:facing]),
          roster,
          ignore_id: entity[:id]
        )
        return nil if conflicts.empty?

        "отряд слишком близко к #{conflicts.map { |entry| entry[:name] }.join(', ')}"
      end
    end
  end
end
