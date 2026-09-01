module Sim
  module Battle
    module Rules
      module Toxin
        module Shooting
          module_function

          def after_hit!(ctx)
            Toxin.apply!(ctx)
          end
        end
      end
    end
  end
end
