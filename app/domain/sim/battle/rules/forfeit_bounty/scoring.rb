module Sim
  module Battle
    module Rules
      module ForfeitBounty
        module Scoring
          # rule: forfeit_bounty | scoring | A deployed company awards its own full cost immediately; attached heroes retain ordinary casualty scoring.
          module_function

          def unit_bounty(unit)
            return unless Array(unit[:abilities]).include?("forfeitBounty")

            own_cost = unit.fetch(:unit_cost, unit[:cost]).to_i
            hero_cost = [ unit[:cost].to_i - own_cost, 0 ].max
            remaining = State.fighting?(unit) ? unit[:models_remaining].to_i : 0
            starting = [ unit[:starting_models].to_i, 1 ].max
            hero_bounty = if remaining <= 0
              hero_cost
            elsif remaining * 2 <= starting
              hero_cost / 2
            else
              0
            end
            own_cost + hero_bounty
          end
        end
      end
    end
  end
end
