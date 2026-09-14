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

      def legal_deployment?(entity, position)
        candidate = footprint_from_entity(entity, x: position[:x], y: position[:y], facing: position[:facing])
        Battlefield.tray_on_battlefield?(candidate) && Battlefield.tray_in_deployment_zone?(candidate)
      end

      # Same gate as a player transform / rotate.
      def clash_reason(entity, position, roster, ignore_id: nil)
        return "отряд не помещается в зоне расстановки" unless legal_deployment?(entity, position)

        slots = Battlefield.sync_formation_slots_from_deployment(position)
        return nil if slots[:row] == "reserve"

        conflicts = conflicting_entities(
          footprint_from_entity(entity, x: position[:x], y: position[:y], facing: position[:facing]),
          roster,
          ignore_id: ignore_id || entity[:id]
        )
        return nil if conflicts.empty?

        "отряд слишком близко к #{conflicts.map { |entry| entry[:name] }.join(', ')}"
      end

      def clear_position?(entity, position, roster, ignore_id: nil)
        clash_reason(entity, position, roster, ignore_id: ignore_id).nil?
      end

      # Largest first, generals before other heroes. Parks everyone in reserve, then
      # fills every legal pose that still fits.
      def pack_roster!(roster)
        units = packable_entities(roster)
        units.each { |entity| park_in_reserve!(entity) }
        units.each_with_index do |entity, index|
          row = Constants::BATTLE_ROWS[[ 2, index / 3 ].min]
          lane = Constants::LANE_ORDER[index % Constants::LANE_ORDER.length]
          position = find_clear_position(entity, row, lane, roster, ignore_id: entity[:id])
          if position
            apply_pack_position!(entity, position)
          else
            park_in_reserve!(entity)
          end
        end
      end

      # Search near the row/lane anchor, then other battle slots, for a legal pose.
      def find_clear_position(entity, preferred_row, preferred_lane, roster, ignore_id: nil)
        facing = entity.dig(:components, :formation, :facing) || 0
        ignore = ignore_id || entity[:id]
        slot_order = [ [ preferred_row, preferred_lane ] ] +
          Constants::BATTLE_ROWS.product(Constants::LANE_ORDER).reject { |row, lane| row == preferred_row && lane == preferred_lane }

        slot_order.each do |row, lane|
          base = Battlefield.default_deployment(row, lane).merge(facing: facing)
          each_deployment_offset(base) do |position|
            return position.merge(row: row, lane: lane) if clear_position?(entity, position, roster, ignore_id: ignore)
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

      def packable_entities(roster)
        roster
          .select { |entry| entry.dig(:state, :current_health).to_i > 0 }
          .reject { |entry| entry[:kind] == "hero" && entry[:state][:attached_to] }
          .sort_by { |entity| pack_sort_key(entity) }
      end

      def pack_sort_key(entity)
        Entities::Footprint.sync_entity!(entity)
        formation = entity[:components][:formation]
        area = -(formation[:width].to_f * formation[:depth].to_f)
        if entity[:kind] == "hero"
          return [ 0, 0, area ] if entity.dig(:components, :hero, :general)

          return [ 1, 0, area ]
        end

        [ 2, 0, area ]
      end

      def park_in_reserve!(entity)
        formation = entity[:components][:formation]
        lane = formation[:lane] || "center"
        position = Battlefield.default_deployment("reserve", lane)
        formation[:row] = "reserve"
        formation[:lane] = lane
        formation[:x] = position[:x]
        formation[:y] = position[:y]
      end

      def apply_pack_position!(entity, position)
        formation = entity[:components][:formation]
        formation[:x] = position[:x]
        formation[:y] = position[:y]
        formation[:facing] = position[:facing] if position[:facing]
        slots = Battlefield.sync_formation_slots_from_deployment(formation)
        formation[:lane] = slots[:lane]
        formation[:row] = slots[:row]
      end
    end
  end
end
