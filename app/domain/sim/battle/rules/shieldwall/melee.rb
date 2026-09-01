module Sim
  module Battle
    module Rules
      module Shieldwall
        module Melee
          module_function

          def damage_factor(attacker, defender, attack_type, vector, _round_number)
            return 1.0 unless attack_type.to_s == "melee"
            return 1.0 unless vector.to_s == "front"
            return 1.0 unless attacker[:charged_distance].to_f.positive?
            return 1.0 unless Array(defender[:abilities]).include?("shieldwall")

            0.75
          end

          def log_clauses(ctx)
            factor = damage_factor(ctx[:attacker], ctx[:defender], ctx[:attack_type], ctx[:vector], 1)
            factor == 1.0 ? [] : [ "щитовая стена ×0.75" ]
          end
        end
      end
    end
  end
end
