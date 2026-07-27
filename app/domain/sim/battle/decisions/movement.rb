module Sim
  module Battle
    module Decisions
      # Melee approach intents: who moves and toward which enemy.
      module Movement
        CONTACT = Pathing::CONTACT
        ADVANCING = { "rear" => "support", "support" => "front" }.freeze

        module_function

        def melee_movers(combatants)
          Roles.active(combatants).select { |entry| Roles.melee_primary?(entry) }
        end

        def nearest_enemy(combatant, enemies)
          candidates = Pathing.active_units(enemies)
          return nil if candidates.empty?

          candidates.min_by { |entry| [ entry[:is_routing] ? 0 : 1, Geometry::Battlefield.distance_between_units(combatant, entry) ] }
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

        def build_approach_intent(combatant:, nearest:, obstacles:)
          return nil unless nearest
          return nil if Geometry::Battlefield.distance_between_units(combatant, nearest) <= CONTACT

          budget = combatant[:movement].to_f
          plan = Pathing.plan_approach(
            origin: combatant,
            goal_point: nearest,
            budget: budget,
            obstacles: obstacles,
            contact_id: nearest[:entity_id],
            goal_unit: nearest
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
              wait: true
            }
          end

          {
            kind: "approach",
            combatant: combatant,
            nearest: nearest,
            plan: plan,
            budget: budget,
            destination: destination,
            wait: false
          }
        end
      end
    end
  end
end
