module Sim
  module Battle
    module Rules
      module Fear
        module Melee
          # rule: fear | melee | Attacker skips melee when fear_cannot_attack is set (failed charge fear check).
          module_function

          def allow_attack?(attacker, _ctx = nil)
            !attacker[:fear_cannot_attack]
          end
        end
      end
    end
  end
end
