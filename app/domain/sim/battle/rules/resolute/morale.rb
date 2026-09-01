module Sim
  module Battle
    module Rules
      module Resolute
        module Morale
          module_function

          def morale_threshold_delta(combatant, _allies, _enemies, combat_score_delta, **)
            return 0 unless combat_score_delta.to_i.positive?

            Array(combatant[:abilities]).include?("resolute") ? 2 : 0
          end
        end
      end
    end
  end
end
