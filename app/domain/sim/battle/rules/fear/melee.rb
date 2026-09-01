module Sim
  module Battle
    module Rules
      module Fear
        # Blocks melee only when a charge fear check failed this round (set in Movement).
        module Melee
          module_function

          def allow_attack?(attacker, _ctx = nil)
            !attacker[:fear_cannot_attack]
          end
        end
      end
    end
  end
end
