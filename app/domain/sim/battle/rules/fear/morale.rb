module Sim
  module Battle
    module Rules
      module Fear
        module Morale
          module_function

          def morale_threshold_delta(_combatant, _allies, enemies, _combat_score_delta)
            enemies.any? { |enemy| Array(enemy[:abilities]).include?("fear") } ? -1 : 0
          end
        end
      end
    end
  end
end
