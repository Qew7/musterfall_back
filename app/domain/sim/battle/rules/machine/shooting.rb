module Sim
  module Battle
    module Rules
      module Machine
        module Shooting
          module_function

          def damage_factor(attacker, _defender, attack_type, _vector, _round_number)
            return 1.0 unless attack_type.to_s == "shooting"
            return 1.0 unless Array(attacker[:abilities]).include?("machine")

            1.25
          end
        end
      end
    end
  end
end
