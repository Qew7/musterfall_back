module Sim
  module Battle
    module Rules
      module Ground
        # Default wheeled / marched melee approach.
        module Movement
          # rule: ground | movement | Default infantry movement AI: charge, flank/rear setup, contact waves, pathfinding.
          module_function

          def plan_entries(movers, enemies, claimed, terrain: [])
            living = Pathing.active_units(enemies)
            ranked = movers.sort_by do |combatant|
              in_arc = Decisions::Movement.enemies_in_front_arc(combatant, living)
              nearest = in_arc.min_by { |entry| Geometry::Battlefield.distance_between_units(combatant, entry) }
              dist = nearest ? Geometry::Battlefield.distance_between_units(combatant, nearest) : Float::INFINITY
              align = nearest ? Decisions::Movement.front_alignment_to(combatant, nearest) : 999.0
              [ align, dist, combatant[:entity_id].to_s ]
            end

            entries_by_id = {}

            ranked.each do |combatant|
              choice = choose_immediate_charge(combatant, living, claimed, terrain)
              next unless choice

              enemy = choice[:nearest]
              side = choice[:contact_slot]
              claimed[enemy[:entity_id]][side] = combatant[:entity_id]
              entries_by_id[combatant[:entity_id]] = Decisions::Movement.build_entry(
                combatant, enemy, side, choice[:approach_mode], chargeable: true
              )
            end

            ranked.each do |combatant|
              next if entries_by_id.key?(combatant[:entity_id])

              choice = choose_natural_side(combatant, living, claimed, terrain)
              next unless choice

              enemy = choice[:nearest]
              side = choice[:contact_slot]
              claimed[enemy[:entity_id]][side] = combatant[:entity_id]
              entries_by_id[combatant[:entity_id]] = Decisions::Movement.build_entry(
                combatant, enemy, side, choice[:approach_mode], chargeable: choice.fetch(:chargeable, true)
              )
            end

            ranked.each do |combatant|
              next if entries_by_id.key?(combatant[:entity_id])

              choice = choose_fallback_target(combatant, living, claimed, terrain)
              next unless choice

              enemy = choice[:nearest]
              side = choice[:contact_slot]
              claimed[enemy[:entity_id]][side] = combatant[:entity_id]
              entries_by_id[combatant[:entity_id]] = Decisions::Movement.build_entry(
                combatant, enemy, side, choice[:approach_mode], chargeable: choice.fetch(:chargeable, true)
              )
            end

            ranked.each do |combatant|
              next if entries_by_id.key?(combatant[:entity_id])

              choice = choose_setup_flank_or_rear(combatant, living, claimed, terrain)
              next unless choice

              enemy = choice[:nearest]
              side = choice[:contact_slot]
              claimed[enemy[:entity_id]][side] = combatant[:entity_id]
              entries_by_id[combatant[:entity_id]] = Decisions::Movement.build_entry(
                combatant, enemy, side, choice[:approach_mode], chargeable: choice.fetch(:chargeable, true)
              )
            end

            ranked.each do |combatant|
              next if entries_by_id.key?(combatant[:entity_id])

              choice = choose_flank_arc_facing(combatant, living, claimed, terrain)
              next unless choice

              enemy = choice[:nearest]
              side = choice[:contact_slot]
              claimed[enemy[:entity_id]][side] = combatant[:entity_id]
              entries_by_id[combatant[:entity_id]] = Decisions::Movement.build_entry(
                combatant, enemy, side, choice[:approach_mode], chargeable: choice.fetch(:chargeable, true)
              )
            end

            ranked.filter_map { |combatant| entries_by_id[combatant[:entity_id]] }.each do |entry|
              entry[:contact_wave] = closing_front?(entry, living)
            end
          end

          # Nearby front claimers settle first; later waves path around their landings.
          def plan_waves(movers, enemies, claimed, terrain: [])
            entries = plan_entries(movers, enemies, claimed, terrain: terrain)
            contact, later = entries.partition { |entry| contact_wave?(entry) }
            waves = contact.group_by { |entry| entry[:nearest][:entity_id] }.map do |_id, group|
              { entries: group, allow_ally_bypass: false }
            end
            waves << { entries: later, allow_ally_bypass: true } if later.any?
            waves
          end

          def contact_wave?(entry)
            !!entry[:contact_wave]
          end

          def slot_path?(origin, defender, contact_slot)
            slot = contact_slot.to_s
            return false if slot.empty?

            Geometry::Battlefield.classify_attack_vector(origin, defender) != slot
          end

          def closing_front?(entry, enemies)
            return false unless entry[:contact_slot] == "front" && entry[:vector] == "front"
            return false if entry[:chargeable] == false
            return false if entry[:contact_slot].to_s != entry[:vector].to_s

            Decisions::Movement.within_charge_range?(entry[:combatant], entry[:nearest], enemies: enemies)
          end

          def choose_immediate_charge(combatant, enemies, claimed, terrain = [])
            return nil if Decisions::Movement.engaged_with_any?(combatant, enemies)

            Pathing.active_units(enemies).sort_by do |enemy|
              [
                Geometry::Battlefield.in_front_arc?(combatant, enemy, combatant[:facing]) ? 0 : 1,
                Decisions::Movement.can_charge?(combatant, enemy, terrain) ? 0 : 1,
                Geometry::Battlefield.distance_between_units(combatant, enemy),
                enemy[:entity_id].to_s
              ]
            end.each do |enemy|
              next unless Decisions::Movement.can_charge?(combatant, enemy, terrain)
              next unless Decisions::Movement.this_turn_charge?(combatant, enemy, enemies: enemies)

              side = Decisions::Movement.unclaimed_side(combatant, enemy, claimed)
              next unless side

              mode = Decisions::Movement.approach_mode_for(side, combatant, enemy)
              return { nearest: enemy, contact_slot: side, approach_mode: mode, chargeable: true }
            end
            nil
          end

          def choose_natural_side(combatant, enemies, claimed, terrain = [])
            candidates = Decisions::Movement.enemies_in_front_arc(combatant, enemies).sort_by do |entry|
              [
                Decisions::Movement.can_charge?(combatant, entry, terrain) ? 0 : 1,
                entry[:is_routing] ? 0 : 1,
                Geometry::Battlefield.distance_between_units(combatant, entry),
                entry[:entity_id].to_s
              ]
            end
            candidates.each do |enemy|
              side = Geometry::Battlefield.classify_attack_vector(combatant, enemy)
              if claimed[enemy[:entity_id]].key?(side)
                return nil if enemy.equal?(candidates.first)

                next
              end

              chargeable = Decisions::Movement.can_charge?(combatant, enemy, terrain)
              return { nearest: enemy, contact_slot: side, approach_mode: :direct, chargeable: chargeable }
            end
            nil
          end

          def choose_fallback_target(combatant, enemies, claimed, terrain = [])
            candidates = Decisions::Movement.enemies_in_front_arc(combatant, enemies).sort_by do |entry|
              [
                Decisions::Movement.can_charge?(combatant, entry, terrain) ? 0 : 1,
                entry[:is_routing] ? 0 : 1,
                Geometry::Battlefield.distance_between_units(combatant, entry),
                entry[:entity_id].to_s
              ]
            end
            return nil if candidates.empty?

            primary = candidates.first
            %w[front flank rear].each do |side|
              next if claimed[primary[:entity_id]].key?(side)
              geo = Geometry::Battlefield.classify_attack_vector(combatant, primary)
              next unless side == geo

              chargeable = Decisions::Movement.can_charge?(combatant, primary, terrain)
              return { nearest: primary, contact_slot: side, approach_mode: :direct, chargeable: chargeable }
            end

            claimed_sides = claimed[primary[:entity_id]]
            chargeable = Decisions::Movement.can_charge?(combatant, primary, terrain)
            unless claimed_sides.key?("flank")
              return { nearest: primary, contact_slot: "flank", approach_mode: :direct, chargeable: chargeable }
            end
            return nil if claimed_sides.key?("rear")

            { nearest: primary, contact_slot: "rear", approach_mode: :direct, chargeable: chargeable }
          end

          def choose_setup_flank_or_rear(combatant, enemies, claimed, terrain = [])
            return nil if Decisions::Movement.engaged_with_any?(combatant, enemies)

            range = Decisions::ChargeRange.setup_radius(combatant, enemies: enemies)
            return nil if range <= 0.05

            candidates = Pathing.active_units(enemies).select do |enemy|
              Geometry::Battlefield.distance_between_units(combatant, enemy) <= range
            end
            return nil if candidates.empty?

            ordered = candidates.sort_by do |enemy|
              geo = Geometry::Battlefield.classify_attack_vector(combatant, enemy)
              geo_rank = %w[flank rear].include?(geo) ? 0 : 1
              [
                Decisions::Movement.can_charge?(combatant, enemy, terrain) ? 0 : 1,
                geo_rank,
                enemy[:is_routing] ? 0 : 1,
                Geometry::Battlefield.distance_between_units(combatant, enemy),
                enemy[:entity_id].to_s
              ]
            end

            ordered.each do |enemy|
              claimed_sides = claimed[enemy[:entity_id]]
              chargeable = Decisions::Movement.can_charge?(combatant, enemy, terrain)
              unless claimed_sides.key?("flank")
                return { nearest: enemy, contact_slot: "flank", approach_mode: :direct, chargeable: chargeable }
              end
              next if claimed_sides.key?("rear")

              return { nearest: enemy, contact_slot: "rear", approach_mode: :direct, chargeable: chargeable }
            end
            nil
          end

          # Front arc empty: nearest enemy on a side flank. Follow already Turn/Wheels onto the heading.
          def choose_flank_arc_facing(combatant, enemies, claimed, terrain = [])
            return nil if Decisions::Movement.engaged_with_any?(combatant, enemies)
            return nil if Decisions::Movement.enemies_in_front_arc(combatant, enemies).any?

            Pathing.active_units(enemies).select do |enemy|
              Geometry::Battlefield.in_flank_arc?(combatant, enemy, combatant[:facing])
            end.sort_by do |enemy|
              [
                Decisions::Movement.can_charge?(combatant, enemy, terrain) ? 0 : 1,
                enemy[:is_routing] ? 0 : 1,
                Geometry::Battlefield.distance_between_units(combatant, enemy),
                enemy[:entity_id].to_s
              ]
            end.each do |enemy|
              side = Decisions::Movement.unclaimed_side(combatant, enemy, claimed)
              next unless side

              chargeable = Decisions::Movement.can_charge?(combatant, enemy, terrain)
              return { nearest: enemy, contact_slot: side, approach_mode: :direct, chargeable: chargeable }
            end
            nil
          end

          def approach_allowed?(combatant, nearest, contact_slot)
            return true if Geometry::Battlefield.in_front_arc?(combatant, nearest, combatant[:facing])
            return true if Geometry::Battlefield.in_flank_arc?(combatant, nearest, combatant[:facing])
            return true if slot_path?(combatant, nearest, contact_slot)

            contact_slot.to_s == Geometry::Battlefield.classify_attack_vector(combatant, nearest)
          end

          def build_approach_intent(combatant:, nearest:, obstacles:, enemies: [], contact_slot: nil, allow_ally_bypass: false, approach_mode: :direct, terrain: [], chargeable: true)
            return nil unless nearest
            return nil if Decisions::Movement.engaged?(combatant, nearest)
            return nil unless approach_allowed?(combatant, nearest, contact_slot)

            charging = chargeable && Decisions::Movement.within_charge_range?(combatant, nearest, enemies: enemies)
            budget = if charging
              Decisions::Movement.charge_budget_for(combatant, enemies: enemies)
            else
              Decisions::Movement.budget_for(combatant, enemies: enemies)
            end
            march_meta = Decisions::Movement.budget_meta(combatant, enemies: enemies)
            goal_point = approach_goal_point(
              combatant, nearest,
              contact_slot: contact_slot,
              approach_mode: approach_mode,
              chargeable: chargeable
            )
            # Forest-hidden: march in without soft-contact until sharing the same forest.
            contact_id = chargeable ? nearest[:entity_id] : nil
            plan = Pathing.plan_approach(
              origin: combatant,
              goal_point: goal_point,
              budget: budget,
              obstacles: obstacles,
              contact_id: contact_id,
              goal_unit: chargeable ? nearest : nil,
              terrain: terrain,
              flying: false,
              # Charge already spends ×2; march on top would be ×4.
              march_allowed: !charging && march_meta[:march].to_s == "active"
            )
            destination = plan[:pose]
            facing_changed = destination && Geometry::Battlefield.shortest_facing_delta(combatant[:facing], destination[:facing]).abs > 0.05
            traveled = destination ? Geometry::Battlefield.distance_between(combatant, destination) : 0.0
            meaningful_move = destination && (facing_changed || traveled > 0.05)
            return nil unless meaningful_move

            Decisions::Movement.approach_intent(
              combatant: combatant,
              nearest: nearest,
              plan: plan,
              budget: budget,
              march_meta: march_meta,
              destination: destination,
              contact_slot: contact_slot,
              approach_mode: approach_mode,
              charge_contact_id: contact_id
            )
          end

          def approach_goal_point(origin, defender, contact_slot:, approach_mode:, chargeable: true)
            slot = contact_slot.to_s
            if slot_path?(origin, defender, slot) && %w[flank rear].include?(slot)
              points = Pathing.contact_slot_points(origin, defender, slot)
              return points.min_by { |point| Geometry::Battlefield.distance_between(origin, point) } if points.any?

              return defender
            end
            return defender unless chargeable

            # Corner charge_destination at ~CONTACT is a 90° hop into the map edge.
            gap = Geometry::Battlefield.distance_between_units(origin, defender)
            return Geometry::Battlefield.move_along_facing(origin, [ gap, 0.5 ].min) if gap <= 1.0

            Geometry::Battlefield.charge_destination(origin, defender)
          end

          def corner_contact_reachable?(origin, defender, budget, terrain: [])
            plan = Pathing.plan_approach(
              origin: origin,
              goal_point: defender,
              budget: budget.to_f,
              obstacles: [ defender ],
              contact_id: defender[:entity_id],
              goal_unit: defender,
              terrain: terrain,
              flying: false
            )
            pose = plan[:pose]
            return false unless pose

            landed = origin.merge(x: pose[:x], y: pose[:y], facing: pose[:facing])
            Geometry::Battlefield.distance_between_units(landed, defender) <= Decisions::Movement::ENGAGE
          end
        end
      end
    end
  end
end
