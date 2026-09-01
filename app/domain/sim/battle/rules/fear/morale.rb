module Sim
  module Battle
    module Rules
      module Fear
        module Morale
          module_function

          def morale_threshold_delta(combatant, _allies, enemies, _combat_score_delta, terrain: [])
            return 0 if has_fear?(combatant) || undaunted?(combatant, terrain: terrain)

            enemies.any? { |enemy| has_fear?(enemy) } ? -1 : 0
          end

          def has_fear?(combatant)
            Array(combatant[:abilities]).include?("fear")
          end

          def undaunted?(combatant, terrain: [])
            return true if Array(combatant[:abilities]).include?("undaunted")

            Wildborn::Morale.undaunted?(combatant, terrain: terrain)
          end
        end
      end
    end
  end
end
