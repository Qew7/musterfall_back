module Sim
  module Battle
    module Rules
      module Charge
        module Melee
          module_function

          def damage_factor(attacker, _defender, attack_type, _vector, _round_number)
            return 1.0 unless attack_type.to_s == "melee"
            return 1.0 if Array(attacker[:abilities]).include?("momentumCharge")
            return 1.0 unless attacker[:charged_distance].to_f.positive?

            1.3
          end

          def log_clauses(ctx)
            factor = damage_factor(ctx[:attacker], ctx[:defender], ctx[:attack_type], ctx[:vector], 1)
            factor == 1.0 ? [] : [ "заряд ×1.3" ]
          end
        end
      end
    end
  end
end
