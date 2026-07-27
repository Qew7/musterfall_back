module Sim
  module Battle
    module Rules
      module Disciplined
        module Morale
          module_function

          def morale_threshold_delta(combatant, _allies, _enemies, _combat_score_delta)
            Array(combatant[:abilities]).include?("disciplined") ? 1 : 0
          end
        end
      end
    end
  end
end
