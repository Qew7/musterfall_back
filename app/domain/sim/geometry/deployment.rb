module Sim
  module Geometry
    module Deployment
      # CONTACT (0.4) is melee range — packing that tight leaves no first step.
      MIN_SEPARATION = 1.0

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
          current_health: entity.dig(:state, :current_health).to_f
        }
      end

      def too_close?(left, right, min_separation: MIN_SEPARATION)
        return true if Battlefield.rectangles_overlap?(left, right)

        Battlefield.distance_between_units(left, right) < min_separation
      end

      def conflicting_entities(candidate, roster, ignore_id: nil)
        roster.select do |entry|
          next false if entry[:id] == ignore_id || entry[:id] == candidate[:entity_id]
          next false if entry.dig(:state, :current_health).to_f <= 0
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

      # Place a combat line first, then support and partners. Every candidate still
      # passes the same geometry checks as manual deployment.
      def pack_roster!(roster)
        units = packable_entities(roster)
        units.each { |entity| park_in_reserve!(entity) }
        placed = []
        role_counts = Hash.new(0)
        row_offsets = Hash.new(0.0)
        units.each do |entity|
          next if ArmyComposition.reserve_for_deployment?(entity, roster)

          role = ArmyComposition.role(ArmyComposition.profile(entity))
          index = role_counts[role]
          role_counts[role] += 1
          row = role == :frontline || role == :flanker ? "front" : "support"
          row = "rear" if role == :artillery
          lanes = role == :flanker ? %w[left right center] : %w[center left right]
          lane = lanes[index % lanes.size]
          partners = ArmyComposition.partners(entity, placed)
          position = find_partner_position(entity, partners, roster)
          unless position || role == :flanker
            width = entity.dig(:components, :formation, :width).to_f
            y = row_offsets[row] + width / 2.0
            Battlefield.default_deployment(row, lane)[:x].to_i.downto(1) do |x|
              candidate = { x: x, y: y, facing: 0 }
              next unless mirrored_position?(entity, candidate) && clear_position?(entity, candidate, roster, ignore_id: entity[:id])

              position = candidate.merge(Battlefield.sync_formation_slots_from_deployment(candidate))
              row_offsets[row] += width + MIN_SEPARATION
              break
            end
          end
          position ||= find_clear_position(entity, row, lane, roster, ignore_id: entity[:id], mirrored: true)
          if position
            apply_pack_position!(entity, position)
            placed << entity
          else
            park_in_reserve!(entity)
          end
        end
      end

      def find_partner_position(entity, partners, roster)
        return nil if partners.empty?

        targets = partners.map { |ally, range, center| [ footprint_from_entity(ally), range, center ] }
        best = nil
        best_coverage = 0
        flanker = ArmyComposition.role(ArmyComposition.profile(entity)) == :flanker
        angles = flanker ? [ 3, 9, 2, 10, 4, 8, 1, 11, 5, 7, 0, 6 ] : [ 6, 5, 7, 4, 8, 3, 9, 2, 10, 1, 11, 0 ]
        # Bounded local search; no pathfinding or battle simulations during packing.
        targets.each do |anchor, _range, _center|
          (1..8).each do |radius|
            angles.each do |step|
              angle = step * Math::PI / 6
              position = { x: anchor[:x] + Math.cos(angle) * radius, y: anchor[:y] + Math.sin(angle) * radius, facing: 0 }
              next unless mirrored_position?(entity, position)
              candidate = footprint_from_entity(entity, **position)
              coverage = targets.count do |target, range, center|
                distance = center ? Battlefield.distance_between(candidate, target) : Battlefield.distance_between_units(candidate, target)
                distance <= range
              end
              next unless coverage > best_coverage
              next unless clear_position?(entity, position, roster, ignore_id: entity[:id])

              best = position.merge(Battlefield.sync_formation_slots_from_deployment(position))
              best_coverage = coverage
              return best if coverage == targets.size
            end
          end
        end
        best
      end

      def mirrored_position?(entity, position)
        return false if Battlefield.sync_formation_slots_from_deployment(position)[:row] == "reserve"

        pose = Battlefield.battle_position(position, 1)
        Battlefield.tray_on_battlefield?(footprint_from_entity(entity, x: pose[:x], y: pose[:y], facing: pose[:facing]))
      end

      # Search near the row/lane anchor, then other battle slots, for a legal pose.
      def find_clear_position(entity, preferred_row, preferred_lane, roster, ignore_id: nil, mirrored: false)
        facing = entity.dig(:components, :formation, :facing) || 0
        ignore = ignore_id || entity[:id]
        slot_order = [ [ preferred_row, preferred_lane ] ] +
          Constants::BATTLE_ROWS.product(Constants::LANE_ORDER).reject { |row, lane| row == preferred_row && lane == preferred_lane }

        slot_order.each do |row, lane|
          base = Battlefield.default_deployment(row, lane).merge(facing: facing)
          each_deployment_offset(base) do |position|
            next unless clear_position?(entity, position, roster, ignore_id: ignore)
            next if mirrored && !mirrored_position?(entity, position)

            return position.merge(row: row, lane: lane)
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
          .select { |entry| entry.dig(:state, :current_health).to_f > 0 }
          .reject { |entry| entry[:kind] == "hero" && entry[:state][:attached_to] }
          .sort_by { |entity| pack_sort_key(entity) }
      end

      def pack_sort_key(entity)
        Entities::Footprint.sync_entity!(entity)
        formation = entity[:components][:formation]
        area = -(formation[:width].to_f * formation[:depth].to_f)
        role = ArmyComposition.role(ArmyComposition.profile(entity))
        priority = { frontline: 0, artillery: 1, supply: 2, flanker: 3, ranged: 4, hero: 5 }.fetch(role)
        [ priority, area ]
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
