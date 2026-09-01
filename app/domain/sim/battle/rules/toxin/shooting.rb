module Sim
  module Battle
    module Rules
      module Toxin
        module Shooting
          # rule: toxin | shooting | Applies toxin debuff after ranged hit.
          module_function

          def after_hit!(ctx)
            Toxin.apply!(ctx)
          end
        end
      end
    end
  end
end
