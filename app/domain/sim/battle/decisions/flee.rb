module Sim
  module Battle
    module Decisions
      # Flee facing and retreat edge intent (Pathing still simulates the path).
      module Flee
        module_function

        # Face directly away from the threat that caused the break (not a blind +180 from current facing).
        def flee_facing_for(combatant, engaged_enemies, enemies)
          threats = Array(engaged_enemies).select { |enemy| enemy[:current_health].nil? || enemy[:current_health].to_i > 0 }
          threats = Array(enemies).select { |enemy| enemy[:current_health].to_i > 0 } if threats.empty?
          return nil if threats.empty?

          heading_away(combatant, threats)
        end

        def heading_away(combatant, enemies)
          center = enemies.each_with_object(x: 0.0, y: 0.0) do |enemy, memo|
            memo[:x] += enemy[:x].to_f
            memo[:y] += enemy[:y].to_f
          end
          average = { x: center[:x] / enemies.length, y: center[:y] / enemies.length }
          Geometry::Battlefield.heading_to(average, combatant)
        end

        def retreat_toward_edge(combatant, distance, obstacles: [], ally_ids: nil, preferred_heading: nil, contact_exempt_ids: nil)
          plan = Pathing.plan_retreat(
            origin: combatant,
            distance: distance,
            obstacles: obstacles,
            ally_ids: ally_ids,
            preferred_heading: preferred_heading,
            contact_exempt_ids: contact_exempt_ids
          )
          destination = plan[:pose] || { x: combatant[:x], y: combatant[:y], facing: combatant[:facing] }
          {
            edge: plan[:edge],
            destination: destination,
            facing: destination[:facing],
            escaped: outside?(destination),
            avoided: plan[:avoided],
            blocked_by_ally: !!plan[:blocked_by_ally],
            blocker: plan[:blocker]
          }
        end

        def outside?(position)
          position[:x] < 0 || position[:y] < 0 ||
            position[:x] > Geometry::Battlefield::CONFIG[:width] - 1 ||
            position[:y] > Geometry::Battlefield::CONFIG[:height] - 1
        end

        def nearest_edge(combatant)
          Pathing.ordered_edges(combatant).first
        end

        def nearest_enemy(combatant, enemies)
          enemies.select { |enemy| enemy[:current_health].to_i > 0 }
            .min_by { |enemy| [ enemy[:is_routing] ? 0 : 1, Geometry::Battlefield.distance_between(combatant, enemy) ] }
        end
      end
    end
  end
end
