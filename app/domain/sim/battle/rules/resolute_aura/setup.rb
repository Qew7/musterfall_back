module Sim
  module Battle
    module Rules
      module ResoluteAura
        module Setup
          # rule: resolute_aura | setup | Attached hero grants host resolute in ability set.
          module_function

          def apply_attach!(host_ctx)
            ability_set = host_ctx[:ability_set]
            return unless ability_set.include?("resoluteAura")

            ability_set << "resolute" unless ability_set.include?("resolute")
          end
        end
      end
    end
  end
end
