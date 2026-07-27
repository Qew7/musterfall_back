module Sim
  module Battle
    module Rules
      module Ferocious
        module Melee
          module_function

          def damage_factor(attacker, _defender, attack_type, _vector, _round_number)
            return 1.0 unless attack_type.to_s == "melee"
            return 1.0 unless Array(attacker[:abilities]).include?("ferocious")

            1.1
          end
        end
      end
    end
  end
end
