module Sim
  module Battle
    module Rules
      module Forestborn
        module Movement
          module_function

          def reposition_mode(combatant, ctx)
            return nil unless Array(combatant[:abilities]).include?("forestborn")
            return nil unless combatant[:ranged].to_i.positive?
            return nil if Geometry::Battlefield.in_forest?(combatant, ctx[:terrain])

            :forest_seek if Array(ctx[:terrain]).any? { |feature| feature[:type].to_s == "forest" }
          end

          def reposition_goals(_combatant, mode, ctx)
            return nil unless mode == :forest_seek

            Array(ctx[:terrain]).filter_map do |feature|
              next unless feature[:type].to_s == "forest"

              { x: feature[:x].to_f, y: feature[:y].to_f, facing: 0.0 }
            end
          end

          def reposition_improves?(_origin, candidate, mode, ctx)
            return nil unless mode == :forest_seek
            return false unless Geometry::Battlefield.in_forest?(candidate, ctx[:terrain])

            board = Array(ctx[:all]).map { |entry| entry[:entity_id] == candidate[:entity_id] ? candidate : entry }
            Decisions::Roles.standing(ctx[:enemies]).any? do |enemy|
              Decisions::Targeting.can_target_ranged?(candidate, enemy, board, terrain: ctx[:terrain])
            end
          end
        end
      end
    end
  end
end
