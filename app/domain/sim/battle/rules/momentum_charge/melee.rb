module Sim
  module Battle
    module Rules
      module MomentumCharge
        module Melee
          module_function

          def damage_factor(attacker, _defender, attack_type, _vector, _round_number)
            return 1.0 unless attack_type.to_s == "melee"
            return 1.0 unless Array(attacker[:abilities]).include?("momentumCharge")

            1.0 + [ attacker[:charged_distance].to_f * 0.05, 0.5 ].min
          end

          def log_clauses(ctx)
            factor = damage_factor(ctx[:attacker], ctx[:defender], ctx[:attack_type], ctx[:vector], 1)
            return [] if factor == 1.0

            percent = ((factor - 1.0) * 100).round
            [ "удар с хода +#{percent}%" ]
          end

          def after_play!(ctx)
            [ ctx[:acting_side], ctx[:target_side] ].each do |side|
              side[:combatants].each do |combatant|
                combatant.delete(:charged_distance)
                combatant.delete(:charged_target_id)
                combatant.delete(:charged_vector)
              end
            end
          end
        end
      end
    end
  end
end
