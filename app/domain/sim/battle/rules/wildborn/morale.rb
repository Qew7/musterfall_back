module Sim
  module Battle
    module Rules
      module Wildborn
        module Morale
          module_function

          def fearless?(combatant, terrain: [])
            return false unless Array(combatant[:abilities]).include?("wildborn")

            Geometry::Battlefield.in_forest?(combatant, terrain)
          end
        end
      end
    end
  end
end
