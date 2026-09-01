module Sim
  module Battle
    module Rules
      module Wildborn
        module Morale
          # rule: wildborn | morale | Counts as fearless while in forest (used by fear morale).
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
