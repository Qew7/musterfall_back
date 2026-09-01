module Sim
  module Battle
    module Rules
      module Toxin
        module Melee
          # rule: toxin | melee | Applies toxin debuff after melee hit.
          module_function

          def after_hit!(ctx)
            Toxin.apply!(ctx)
          end
        end
      end
    end
  end
end
