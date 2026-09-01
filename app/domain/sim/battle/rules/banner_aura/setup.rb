module Sim
  module Battle
    module Rules
      module BannerAura
        module Setup
          # rule: banner_aura | setup | Hero bannerAura on attach: +1 melee to host and first melee contributor.
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
