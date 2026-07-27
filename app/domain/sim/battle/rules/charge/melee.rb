module Sim
  module Battle
    module Rules
      module Charge
        module Melee
          module_function

          def damage_factor(attacker, _defender, attack_type, _vector, round_number)
            return 1.0 unless attack_type.to_s == "melee"
            return 1.0 unless round_number.to_i == 1
            return 1.0 unless Array(attacker[:abilities]).include?("charge")

            1.3
          end
        end
      end
    end
  end
end
