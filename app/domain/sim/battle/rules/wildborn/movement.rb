module Sim
  module Battle
    module Rules
      module Wildborn
        module Movement
          # rule: wildborn | movement | Fearless in forest; may charge through terrain toward forest targets.
          module_function

          def can_charge_through_terrain?(attacker, defender, terrain)
            return false unless Array(attacker[:abilities]).include?("wildborn")

            Geometry::Battlefield.in_forest?(defender, terrain)
          end

          def fearless?(combatant, terrain: [])
            return false unless Array(combatant[:abilities]).include?("wildborn")

            Geometry::Battlefield.in_forest?(combatant, terrain)
          end
        end
      end
    end
  end
end
