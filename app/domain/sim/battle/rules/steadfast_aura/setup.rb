module Sim
  module Battle
    module Rules
      module SteadfastAura
        module Setup
          module_function

          def apply_attach!(host_ctx)
            ability_set = host_ctx[:ability_set]
            return unless ability_set.include?("steadfastAura")

            ability_set << "steadfast" unless ability_set.include?("steadfast")
          end
        end
      end
    end
  end
end
