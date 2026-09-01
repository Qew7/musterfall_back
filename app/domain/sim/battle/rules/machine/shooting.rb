module Sim
  module Battle
    module Rules
      module Machine
        module Shooting
          # rule: machine | shooting | Machine ranged damage ×1.25.
          module_function

          def damage_factor(attacker, _defender, attack_type, _vector, _round_number)
            return 1.0 unless attack_type.to_s == "shooting"
            return 1.0 unless Array(attacker[:abilities]).include?("machine")

            1.25
          end

          def log_clauses(ctx)
            factor = damage_factor(ctx[:attacker], ctx[:defender], ctx[:attack_type], ctx[:vector], 1)
            factor == 1.0 ? [] : [ "осадная машина ×1.25" ]
          end
        end
      end
    end
  end
end
