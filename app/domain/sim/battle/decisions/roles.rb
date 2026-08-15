module Sim
  module Battle
    module Decisions
      # Combat role helpers shared by movement / reposition policies.
      module Roles
        module_function

        # Still on the field (HP > 0). Name avoids "living" — undead armies count too.
        def standing(combatants)
          Array(combatants).select { |entry| entry[:current_health].to_i > 0 }
        end

        def active(combatants)
          standing(combatants).reject { |entry| entry[:is_routing] }
        end

        def melee_primary?(combatant)
          combatant[:melee].to_i > combatant[:ranged].to_i + combatant[:spell].to_i
        end

        def missile_seeker?(combatant)
          return false if melee_primary?(combatant)

          combatant[:ranged].to_i > 0 || combatant[:spell].to_i > 0
        end
      end
    end
  end
end
