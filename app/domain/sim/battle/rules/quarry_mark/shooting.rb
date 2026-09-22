module Sim
  module Battle
    module Rules
      module QuarryMark
        module Shooting
          # rule: quarry_mark | shooting | The first two successful volleys mark a target; the next different allied attacker consumes it for one missed-hit reroll.
          module_function

          def before_attack!(ctx)
            Melee.before_attack!(ctx)
          end

          def reroll_miss?(ctx)
            Melee.reroll_miss?(ctx)
          end

          def after_hit!(ctx)
            Melee.after_hit!(ctx)
          end

          def missed_hit_rerolls(...)
            Melee.missed_hit_rerolls(...)
          end
        end
      end
    end
  end
end
