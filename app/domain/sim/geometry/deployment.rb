module Sim
  module Geometry
    module Deployment
      MIN_SEPARATION = Battlefield::CONFIG[:melee_contact_tolerance]

      module_function

      def footprint_from_entity(entity, x: nil, y: nil, facing: nil)
        Entities::Footprint.sync_entity!(entity)
        formation = entity[:components][:formation]
        {
          entity_id: entity[:id],
          name: entity[:name],
          x: (x.nil? ? formation[:x] : x).to_f,
          y: (y.nil? ? formation[:y] : y).to_f,
          facing: Battlefield.normalize_facing(facing.nil? ? formation[:facing] : facing),
          base_width: formation[:width].to_f,
          base_depth: formation[:depth].to_f,
          current_health: entity.dig(:state, :current_health).to_i
        }
      end

      def too_close?(left, right, min_separation: MIN_SEPARATION)
        return true if Battlefield.rectangles_overlap?(left, right)

        Battlefield.distance_between_units(left, right) < min_separation
      end

      def conflicting_entities(candidate, roster, ignore_id: nil)
        roster.select do |entry|
          next false if entry[:id] == ignore_id || entry[:id] == candidate[:entity_id]
          next false if entry.dig(:state, :current_health).to_i <= 0
          next false if entry[:kind] == "hero" && entry[:state][:attached_to]
          next false if entry.dig(:components, :formation, :row) == "reserve"

          too_close?(candidate, footprint_from_entity(entry))
        end
      end

      def clear_position?(entity, position, roster, ignore_id: nil)
        candidate = footprint_from_entity(entity, x: position[:x], y: position[:y], facing: position[:facing])
        conflicting_entities(candidate, roster, ignore_id: ignore_id || entity[:id]).empty?
      end

      # Search near the row/lane anchor, then other battle slots, for a non-glued pose.
      def find_clear_position(entity, preferred_row, preferred_lane, roster, ignore_id: nil)
        facing = entity.dig(:components, :formation, :facing) || 0
        slot_order = [ [ preferred_row, preferred_lane ] ] +
          Constants::BATTLE_ROWS.product(Constants::LANE_ORDER).reject { |row, lane| row == preferred_row && lane == preferred_lane }

        slot_order.each do |row, lane|
          base = Battlefield.default_deployment(row, lane).merge(facing: facing)
          each_deployment_offset(base) do |position|
            return position.merge(row: row, lane: lane) if clear_position?(entity, position, roster, ignore_id: ignore_id || entity[:id])
          end
        end

        nil
      end

      def each_deployment_offset(base)
        yield base
        (1..12).each do |radius|
          (-radius..radius).each do |dx|
            [ radius, -radius ].each do |dy|
              yield Battlefield.clamp_deployment_position(x: base[:x] + dx, y: base[:y] + dy, facing: base[:facing])
            end
          end
          ((-radius + 1)...radius).each do |dy|
            [ radius, -radius ].each do |dx|
              yield Battlefield.clamp_deployment_position(x: base[:x] + dx, y: base[:y] + dy, facing: base[:facing])
            end
          end
        end
      end
    end
  end
end
