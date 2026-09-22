module Sim
  module Battle
    module Rules
      module ChargeBarricade
        module Movement
          # rule: charge_barricade | movement | Brace against nearby momentum chargers; moving or turning prevents barricade protection until the next stationary movement phase.
          module_function

          def movement_multiplier(combatant, ctx)
            return 1.0 unless Array(combatant[:abilities]).include?("chargeBarricade")

            threat = Array(ctx[:enemies]).any? do |enemy|
              enemy[:current_health].to_f.positive? && !enemy[:is_routing] &&
                Array(enemy[:abilities]).include?("momentumCharge") &&
                Geometry::Battlefield.distance_between_units(combatant, enemy) <= enemy[:movement].to_f * 2 + 1 &&
                Geometry::Battlefield.in_front_arc?(combatant, enemy, combatant[:facing])
            end
            threat ? 0.0 : 1.0
          end

          def after_play!(ctx)
            ctx[:acting_side][:combatants].each do |combatant|
              next unless Array(combatant[:abilities]).include?("chargeBarricade")

              moved = ctx[:phase][:actions].any? do |action|
                action[:type] == "movement" && action[:actor_id] == combatant[:entity_id] &&
                  (Geometry::Battlefield.distance_between(action[:from], action[:to]) > 0.05 ||
                    Geometry::Battlefield.shortest_facing_delta(action[:from][:facing], action[:to][:facing]).abs > 0.05)
              end
              combatant[:barricade_braced] = !moved
            end
          end
        end
      end
    end
  end
end
