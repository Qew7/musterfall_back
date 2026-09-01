module Sim
  module Battle
    module Rules
      module Forestborn
        module Shooting
          # rule: forestborn | shooting | +1 shooting skill when target is in forest.
          module_function

          def shooting_skill(attacker, defender, terrain, skill)
            return skill unless Array(attacker[:abilities]).include?("forestborn")
            return skill unless Geometry::Battlefield.in_forest?(defender, terrain)

            skill + 1
          end

          def log_clauses(ctx)
            return [] unless Array(ctx[:attacker][:abilities]).include?("forestborn")
            return [] unless Geometry::Battlefield.in_forest?(ctx[:defender], ctx[:terrain])

            [ "без штрафа стрельбы в лес" ]
          end
        end
      end
    end
  end
end
