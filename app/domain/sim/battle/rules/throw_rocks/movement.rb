module Sim
  module Battle
    module Rules
      module ThrowRocks
        module Movement
          # rule: throw_rocks | movement | Non-melee mover advances when no line of sight for ranged throw.
          module_function

          def melee_mover?(combatant)
            return nil unless Array(combatant[:abilities]).include?("throwRocks")

            false
          end

          def reposition_mode(combatant, ctx)
            return nil unless Array(combatant[:abilities]).include?("throwRocks")

            board = ctx[:all]
            can_shoot = Decisions::Roles.standing(ctx[:enemies]).any? do |enemy|
              Decisions::Targeting.can_target_ranged?(combatant, enemy, board, terrain: ctx[:terrain])
            end
            :rock_seek unless can_shoot
          end

          def reposition_goals(combatant, mode, ctx)
            return nil unless mode == :rock_seek

            target = Decisions::Roles.standing(ctx[:enemies])
              .min_by { |enemy| Geometry::Battlefield.distance_between(combatant, enemy) }
            return [] unless target

            heading = Geometry::Battlefield.heading_to(combatant, target)
            forward = Geometry::Battlefield.facing_vector(heading)
            step = [ ctx[:budget].to_f, Geometry::Battlefield.distance_between(combatant, target) ].min
            [ 1.0, 0.75, 0.5 ].map do |scale|
              Geometry::Battlefield.clamp_battlefield_position(
                x: combatant[:x].to_f + (forward[:x] * step * scale),
                y: combatant[:y].to_f + (forward[:y] * step * scale),
                facing: heading
              )
            end
          end

          def reposition_improves?(origin, candidate, mode, ctx)
            return nil unless mode == :rock_seek

            target = Decisions::Roles.standing(ctx[:enemies])
              .min_by { |enemy| Geometry::Battlefield.distance_between(origin, enemy) }
            return false unless target

            before = Geometry::Battlefield.distance_between(origin, target)
            after = Geometry::Battlefield.distance_between(candidate, target)
            after < before - 0.05
          end
        end
      end
    end
  end
end
