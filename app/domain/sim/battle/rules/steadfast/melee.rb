module Sim
  module Battle
    module Rules
      module Steadfast
        module Melee
          module_function

          def damage_factor(_attacker, defender, _attack_type, vector, _round_number)
            return 1.0 unless vector.to_s == "front"
            return 1.0 unless Array(defender[:abilities]).include?("steadfast")

            0.85
          end
        end
      end
    end
  end
end
