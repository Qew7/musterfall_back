module Sim
  module Battle
    module Rules
      module RuneArmor
        module Shooting
          # rule: rune_armor | shooting | Non-magic ranged damage ×⅔.
          module_function

          def damage_factor(_attacker, defender, attack_type, _vector, _round_number)
            return 1.0 if attack_type.to_s == "magic"
            return 1.0 unless Array(defender[:abilities]).include?("runeArmor")

            2.0 / 3.0
          end

          def log_clauses(ctx)
            factor = damage_factor(ctx[:attacker], ctx[:defender], ctx[:attack_type], ctx[:vector], 1)
            factor == 1.0 ? [] : [ "рунические доспехи ×⅔" ]
          end
        end
      end
    end
  end
end
