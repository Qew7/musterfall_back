module Sim
  module Battle
    module Decisions
      # Charge setup / reach: 2×MV budget and distance gates used by movement planners.
      module ChargeRange
        SETUP_MV = 2.0

        module_function

        def gap(combatant, enemy)
          Geometry::Battlefield.distance_between_units(combatant, enemy)
        end

        def budget(combatant, enemies: [])
          Movement.budget_for(combatant, enemies: enemies) * SETUP_MV
        end

        # Max gap closable on a charge this turn (2×MV + contact band).
        def reach(combatant, enemies: [])
          budget(combatant, enemies: enemies) + Movement::ENGAGE
        end

        # Orbit/setup radius without the contact snap band.
        def setup_radius(combatant, enemies: [])
          budget(combatant, enemies: enemies)
        end

        def within?(combatant, enemy, enemies: [])
          gap(combatant, enemy) <= reach(combatant, enemies: enemies)
        end
      end
    end
  end
end
