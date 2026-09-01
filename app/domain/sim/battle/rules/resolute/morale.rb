module Sim
  module Battle
    module Rules
      module Resolute
        module Morale
          # rule: resolute | morale | +2 break threshold when combat score is positive; undead only while general lives.
          module_function

          def morale_threshold_delta(combatant, allies, _enemies, combat_score_delta, **)
            return 0 unless combat_score_delta.to_i.positive?
            return 0 unless Array(combatant[:abilities]).include?("resolute")
            return 0 if undead_resolute?(combatant) && !Undead.general_alive?(allies)

            2
          end

          def undead_resolute?(combatant)
            Array(combatant[:abilities]).include?("undead")
          end
          private_class_method :undead_resolute?
        end
      end
    end
  end
end
