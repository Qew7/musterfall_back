module Sim
  module Battle
    module Rules
      module BannerAura
        module Setup
          module_function

          def apply_attach!(host_ctx)
            ability_set = host_ctx[:ability_set]
            return unless ability_set.include?("bannerAura")

            host_ctx[:melee] += 1
            host_ctx[:melee_contributors][0][:power] += 1
          end
        end
      end
    end
  end
end
