module Sim
  module Battle
    module Decisions
      # Melee approach intents: who moves and toward which enemy.
      module Movement
        CONTACT = Pathing::CONTACT
        CONTACT_SNAP = Geometry::Battlefield::CONFIG[:contact_snap]
        # Fight / stop-approaching band (closes the microscopic dead zone at CONTACT).
        ENGAGE = CONTACT + CONTACT_SNAP
        ADVANCING = { "rear" => "support", "support" => "front" }.freeze
        SLOT_RANK = { "front" => 0, "flank" => 1, "rear" => 2 }.freeze

        module_function

        def melee_movers(combatants)
          Roles.active(combatants).select { |entry| Roles.melee_primary?(entry) }
        end

        def nearest_enemy(combatant, enemies)
          candidates = Pathing.active_units(enemies)
          return nil if candidates.empty?

          candidates.min_by { |entry| [ entry[:is_routing] ? 0 : 1, Geometry::Battlefield.distance_between_units(combatant, entry) ] }
        end

        def engaged?(combatant, enemy)
          return false unless enemy

          Geometry::Battlefield.distance_between_units(combatant, enemy) <= ENGAGE
        end

        def row_advance_target(combatant, allies)
          target_row = ADVANCING[combatant[:row]]
          return nil unless target_row

          occupied = allies.any? do |entry|
            entry[:current_health].to_i > 0 &&
              entry[:entity_id] != combatant[:entity_id] &&
              entry[:lane] == combatant[:lane] &&
              entry[:row] == target_row
          end
          return nil if occupied

          target_row
        end

        # Tag each mover with nearest target + contact slot (front/flank/rear) among allies
        # that share the same enemy. Closest / most frontal claims front; others take geometry.
        def plan_melee_entries(movers, enemies)
          entries = movers.filter_map do |combatant|
            nearest = nearest_enemy(combatant, enemies)
            next unless nearest

            {
              combatant: combatant,
              nearest: nearest,
              distance: Geometry::Battlefield.distance_between_units(combatant, nearest),
              vector: Geometry::Battlefield.classify_attack_vector(combatant, nearest)
            }
          end
          assign_contact_slots!(entries)
          entries
        end

        def assign_contact_slots!(entries)
          entries.group_by { |entry| entry[:nearest][:entity_id] }.each_value do |group|
            ordered = group.sort_by do |entry|
              [
                front_alignment(entry),
                entry[:distance],
                entry[:combatant][:entity_id].to_s
              ]
            end
            ordered.each_with_index do |entry, index|
              geo = entry[:vector]
              entry[:contact_slot] =
                if index.zero?
                  "front"
                elsif geo == "rear"
                  "rear"
                else
                  "flank"
                end
            end
          end
          entries
        end

        # Smaller = more frontal relative to the defender.
        def front_alignment(entry)
          angle = Geometry::Battlefield.angle_between(
            entry[:nearest][:facing],
            entry[:nearest],
            entry[:combatant]
          )
          angle.to_f
        end

        def contact_wave?(entry)
          # Geometric flank/rear always waits for the second pass so they can slip around
          # friends who already claimed the front.
          return false if entry[:vector] == "flank" || entry[:vector] == "rear"
          return true if entry[:distance] <= ENGAGE + entry[:combatant][:movement].to_f * 0.35
          return true if entry[:contact_slot] == "front"

          false
        end

        def build_approach_intent(combatant:, nearest:, obstacles:, contact_slot: nil, allow_ally_bypass: false)
          return nil unless nearest
          return nil if engaged?(combatant, nearest)

          budget = combatant[:movement].to_f
          goal_point = slot_approach_point(combatant, nearest, contact_slot) || nearest
          plan = Pathing.plan_approach(
            origin: combatant,
            goal_point: goal_point,
            budget: budget,
            obstacles: obstacles,
            contact_id: nearest[:entity_id],
            goal_unit: nearest,
            allow_ally_bypass: allow_ally_bypass
          )
          destination = plan[:pose]
          facing_changed = destination && Geometry::Battlefield.shortest_facing_delta(combatant[:facing], destination[:facing]).abs > 0.05
          traveled = destination ? Geometry::Battlefield.distance_between(combatant, destination) : 0.0
          meaningful_move = destination && (facing_changed || traveled > 0.05)

          if !meaningful_move
            return nil unless plan[:blocked_by_ally] && plan[:blocker]

            return {
              kind: "approach",
              combatant: combatant,
              nearest: nearest,
              plan: plan,
              budget: budget,
              destination: nil,
              wait: true,
              contact_slot: contact_slot
            }
          end

          {
            kind: "approach",
            combatant: combatant,
            nearest: nearest,
            plan: plan,
            budget: budget,
            destination: destination,
            wait: false,
            contact_slot: contact_slot
          }
        end

        # Bias flank/rear claimers toward the matching face of the defender — but only when
        # they are already geometrically on that face. Assigned-slot-only (still in front of
        # the enemy) keeps a direct charge so we do not yank them sideways into friends.
        def slot_approach_point(origin, defender, slot)
          return nil if slot.nil? || slot == "front"

          geo = Geometry::Battlefield.classify_attack_vector(origin, defender)
          return nil unless geo == "flank" || geo == "rear"

          points = Pathing.contact_slot_points(origin, defender, slot)
          return nil if points.empty?

          points.min_by { |point| Geometry::Battlefield.distance_between(origin, point) }
        end
      end
    end
  end
end
