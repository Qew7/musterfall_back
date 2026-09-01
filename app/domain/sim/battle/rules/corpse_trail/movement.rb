module Sim
  module Battle
    module Rules
      module CorpseTrail
        # Legacy corpse_mire terrain from older battles/replays.
        module Movement
          module_function

          def terrain_damage_factor(combatant, feature)
            return 1.0 unless feature[:rule_key].to_s == "corpseTrail"
            return 0.0 if Array(combatant[:abilities]).include?("undead")

            1.0
          end
        end
      end
    end
  end
end
