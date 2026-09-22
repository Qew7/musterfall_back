module Sim
  module Battle
    module Rules
      module BodyguardContract
        module Shooting
          # rule: bodyguard_contract | shooting | Once per battle, a nearby standing guard takes up to 3 actual incoming allied ranged damage without further mitigation.
          module_function

          def before_damage!(ctx)
            Melee.before_damage!(ctx)
          end
        end
      end
    end
  end
end
