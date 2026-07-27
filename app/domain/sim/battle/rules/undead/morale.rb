module Sim
  module Battle
    module Rules
      module Undead
        module Morale
          module_function

          def handle_morale_failure!(combatant, check, _ctx)
            return false unless Array(combatant[:abilities]).include?("undead")

            damage = check[:failure_margin].to_i
            combatant[:current_health] = [ 0, combatant[:current_health] - damage ].max
            State.sync_combatant_footprint!(combatant)
            {
              damage: damage,
              summary: "#{combatant[:name]} проваливает проверку морали и теряет #{damage} здоровья вместо бегства."
            }
          end
        end
      end
    end
  end
end
