module Sim
  module Battle
    module Rules
      module Ground
        # Default wheeled / marched melee approach.
        module Movement
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
              choice = choose_natural_side(combatant, living, claimed, terrain)
              next unless choice

              enemy = choice[:nearest]
              side = choice[:contact_slot]
              claimed[enemy[:entity_id]][side] = combatant[:entity_id]
              entries_by_id[combatant[:entity_id]] = Decisions::Movement.build_entry(
                combatant, enemy, side, :direct, chargeable: choice.fetch(:chargeable, true)
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

            ranked.filter_map { |combatant| entries_by_id[combatant[:entity_id]] }
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
              next if claimed[enemy[:entity_id]].key?(side)

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

            candidates.each do |enemy|
              %w[front flank rear].each do |side|
                next if claimed[enemy[:entity_id]].key?(side)
                geo = Geometry::Battlefield.classify_attack_vector(combatant, enemy)
                next unless side == geo

                chargeable = Decisions::Movement.can_charge?(combatant, enemy, terrain)
                return { nearest: enemy, contact_slot: side, approach_mode: :direct, chargeable: chargeable }
              end
            end

            primary = candidates.first
            claimed_sides = claimed[primary[:entity_id]]
            chargeable = Decisions::Movement.can_charge?(combatant, primary, terrain)
            unless claimed_sides.key?("flank")
              return { nearest: primary, contact_slot: "flank", approach_mode: :orbit_flank, chargeable: chargeable }
            end
            return nil if claimed_sides.key?("rear")

            { nearest: primary, contact_slot: "rear", approach_mode: :wrap_rear, chargeable: chargeable }
          end

          def choose_setup_flank_or_rear(combatant, enemies, claimed, terrain = [])
            return nil if Decisions::Movement.engaged_with_any?(combatant, enemies)

            budget = Decisions::Movement.budget_for(combatant, enemies: enemies)
            range = budget * Decisions::Movement::SETUP_RANGE_MV
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
                return { nearest: enemy, contact_slot: "flank", approach_mode: :orbit_flank, chargeable: chargeable }
              end
              next if claimed_sides.key?("rear")

              return { nearest: enemy, contact_slot: "rear", approach_mode: :wrap_rear, chargeable: chargeable }
            end
            nil
          end

          def build_approach_intent(combatant:, nearest:, obstacles:, enemies: [], contact_slot: nil, allow_ally_bypass: false, approach_mode: :direct, terrain: [], chargeable: true)
            return nil unless nearest
            return nil if Decisions::Movement.engaged?(combatant, nearest)
            return nil unless Geometry::Battlefield.in_front_arc?(combatant, nearest, combatant[:facing]) || Decisions::Movement.orbit_mode?(approach_mode)

            budget = Decisions::Movement.budget_for(combatant, enemies: enemies)
            march_meta = Decisions::Movement.budget_meta(combatant, enemies: enemies)
            goal_point = approach_goal_point(combatant, nearest, contact_slot: contact_slot, approach_mode: approach_mode)
            # Forest-hidden: march in without soft-contact until sharing the same forest.
            contact_id = chargeable ? nearest[:entity_id] : nil
            plan = Pathing.plan_approach(
              origin: combatant,
              goal_point: goal_point,
              budget: budget,
              obstacles: obstacles,
              contact_id: contact_id,
              goal_unit: chargeable ? nearest : nil,
              approach_mode: approach_mode,
              contact_slot: contact_slot,
              terrain: terrain,
              flying: false,
              march_allowed: march_meta[:march].to_s == "active"
            )
            destination = plan[:pose]
            facing_changed = destination && Geometry::Battlefield.shortest_facing_delta(combatant[:facing], destination[:facing]).abs > 0.05
            traveled = destination ? Geometry::Battlefield.distance_between(combatant, destination) : 0.0
            meaningful_move = destination && (facing_changed || traveled > 0.05)
            return nil unless meaningful_move

            {
              kind: "approach",
              combatant: combatant,
              nearest: nearest,
              plan: plan,
              budget: budget,
              march_meta: march_meta,
              destination: destination,
              wait: false,
              contact_slot: contact_slot,
              approach_mode: approach_mode,
              charge_contact_id: contact_id
            }
          end

          def approach_goal_point(origin, defender, contact_slot:, approach_mode:)
            slot =
              case approach_mode
              when :orbit_flank then "flank"
              when :wrap_rear then "rear"
              else contact_slot.to_s
              end
            return defender unless Decisions::Movement.orbit_mode?(approach_mode) && %w[flank rear].include?(slot)

            points = Pathing.contact_slot_points(origin, defender, slot)
            return points.min_by { |point| Geometry::Battlefield.distance_between(origin, point) } if points.any?

            defender
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
