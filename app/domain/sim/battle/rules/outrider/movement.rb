module Sim
  module Battle
    module Rules
      module Outrider
        module Movement
          module_function

          def melee_mover?(combatant)
            return nil unless Array(combatant[:abilities]).include?("outrider")

            false
          end

          def reposition_mode(combatant, ctx)
            return nil unless Array(combatant[:abilities]).include?("outrider")

            target = nearest(combatant, ctx[:enemies])
            return nil unless target

            distance = Geometry::Battlefield.distance_between(combatant, target)
            shot = Decisions::Targeting.can_target_ranged?(combatant, target, ctx[:all], terrain: ctx[:terrain])
            :outrider_kite unless shot && distance.between?(min_range(combatant), combatant[:shooting_range].to_f)
          end

          def reposition_goals(combatant, mode, ctx)
            return nil unless mode == :outrider_kite

            target = nearest(combatant, ctx[:enemies])
            return [] unless target

            away = Geometry::Battlefield.heading_to(target, combatant)
            [ away, away + 25, away - 25 ].map do |heading|
              vector = Geometry::Battlefield.facing_vector(heading)
              Geometry::Battlefield.clamp_battlefield_position(
                x: target[:x].to_f + (vector[:x] * ideal_range(combatant)),
                y: target[:y].to_f + (vector[:y] * ideal_range(combatant)),
                facing: Geometry::Battlefield.heading_to(combatant, target)
              )
            end
          end

          def reposition_improves?(_origin, candidate, mode, ctx)
            return nil unless mode == :outrider_kite

            target = nearest(candidate, ctx[:enemies])
            return false unless target

            distance = Geometry::Battlefield.distance_between(candidate, target)
            distance.between?(min_range(candidate), candidate[:shooting_range].to_f) &&
              Decisions::Targeting.can_target_ranged?(candidate, target, replace(ctx[:all], candidate), terrain: ctx[:terrain])
          end

          def ideal_range(combatant)
            [ combatant[:shooting_range].to_f - 1.0, 6.0 ].max
          end
          private_class_method :ideal_range

          def min_range(combatant)
            [ combatant[:shooting_range].to_f - 3.0, 4.0 ].max
          end
          private_class_method :min_range

          def nearest(combatant, enemies)
            Decisions::Roles.standing(enemies).min_by { |enemy| Geometry::Battlefield.distance_between(combatant, enemy) }
          end
          private_class_method :nearest

          def replace(all, combatant)
            Array(all).map { |entry| entry[:entity_id] == combatant[:entity_id] ? combatant : entry }
          end
          private_class_method :replace
        end
      end
    end
  end
end
