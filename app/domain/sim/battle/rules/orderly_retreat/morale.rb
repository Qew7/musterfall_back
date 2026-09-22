module Sim
  module Battle
    module Rules
      module OrderlyRetreat
        module Morale
          DISTANCE = 1.0

          # rule: orderly_retreat | morale | The first failed melee morale check becomes a legal 1-inch backward withdrawal without routing or changing facing; a blocked retreat fails normally.
          module_function

          def army_role(profile)
            :frontline if Array(profile[:abilities]).include?("orderlyRetreat")
          end

          def handle_morale_failure!(combatant, _check, ctx)
            return unless Array(combatant[:abilities]).include?("orderlyRetreat")
            return unless ctx[:phase_type] == "melee" && !combatant[:is_routing] && !combatant[:orderly_retreat_used]

            # The first failure spends the attempt even when the rear is blocked.
            combatant[:orderly_retreat_used] = true
            vector = Geometry::Battlefield.facing_vector(combatant[:facing])
            destination = combatant.merge(
              x: combatant[:x].to_f - vector[:x] * DISTANCE,
              y: combatant[:y].to_f - vector[:y] * DISTANCE
            )
            units = ctx[:all_combatants] || Array(ctx[:allies]) + Array(ctx[:enemies])
            world = Pathing::Obstacles.around(combatant, units: units, terrain: Array(ctx[:terrain]))
            return unless world.clear?(destination)

            contacts = Array(ctx[:engaged_enemies]).select { |enemy| Geometry::Battlefield.melee_contact?(combatant, enemy) }
            return unless contacts.all? do |enemy|
              Geometry::Battlefield.distance_between_units(destination, enemy) > Geometry::Battlefield.distance_between_units(combatant, enemy)
            end
            path_world = world.except(contacts.map { |enemy| enemy[:entity_id] })
            return unless path_world.translation_clear?(combatant, combatant, destination)

            combatant[:x] = destination[:x]
            combatant[:y] = destination[:y]
            State.sync_combatant_footprint!(combatant)
            {
              damage: 0, result: "orderly_retreat",
              summary: "#{combatant[:name]} отступают на 1″, сохраняя строй и выдержку.",
              details: [ "orderly_retreat distance=#{DISTANCE} used=true routing=false facing=#{combatant[:facing]}" ]
            }
          end
        end
      end
    end
  end
end
