module Sim
  module Battle
    module Rules
      module Dodge
        module Melee
          module_function

          def hit_chance_factor(_attacker, defender, _attack_type)
            Array(defender[:abilities]).include?("dodge") ? 0.8 : 1.0
          end
        end
      end
    end
  end
end
