module Sim
  module Battle
    module Rules
      module Skirmisher
        module Melee
          module_function

          def facing_damage_factor(defender, _vector)
            return 1.0 if Array(defender[:abilities]).include?("skirmisher")

            nil
          end

          def requires_front_arc_for_ranged?(attacker)
            abilities = Array(attacker[:targeting_abilities] || attacker[:abilities])
            !abilities.include?("skirmisher")
          end
        end
      end
    end
  end
end
