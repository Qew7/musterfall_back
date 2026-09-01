module Sim
  module Battle
    module Rules
      module AntiLarge
        module Melee
          module_function

          def damage_factor(attacker, defender, attack_type, _vector, _round_number)
            return 1.0 unless attack_type.to_s == "melee"
            return 1.0 unless Array(attacker[:abilities]).include?("antiLarge")
            return 1.0 unless defender[:model_class].to_s.in?(%w[monster cavalry])

            1.35
          end

          def log_clauses(ctx)
            factor = damage_factor(ctx[:attacker], ctx[:defender], ctx[:attack_type], ctx[:vector], 1)
            factor == 1.0 ? [] : [ "против крупной цели ×1.35" ]
          end
        end
      end
    end
  end
end
