module Sim
  module Battle
    module Rules
      module AntiFlying
        module Shooting
          # rule: anti_flying | shooting | Machine ranged damage ×0.5 vs flying targets.
          module_function

          def damage_factor(attacker, defender, attack_type, _vector, _round_number)
            return 1.0 unless attack_type.to_s == "shooting"
            return 1.0 unless Array(attacker[:abilities]).include?("antiFlying")
            return 1.0 unless Array(defender[:abilities]).include?("flying")

            0.5
          end

          def log_clauses(ctx)
            factor = damage_factor(ctx[:attacker], ctx[:defender], ctx[:attack_type], ctx[:vector], 1)
            factor == 1.0 ? [] : [ "противовоздушная ×0.5" ]
          end
        end
      end
    end
  end
end
