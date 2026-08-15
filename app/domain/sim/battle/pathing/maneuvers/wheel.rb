module Sim
  module Battle
    module Pathing
      module Maneuvers
        module Wheel
          module_function

          def key
            :wheel
          end

          def applies?(origin, heading, budget)
            return false if budget.to_f <= 0.05

            Geometry::Battlefield.shortest_facing_delta(origin[:facing], heading).abs > 0.05
          end

          def simulate(origin:, heading:, budget:, goal_point:, goal_unit:, obstacles:, contact_id:, terrain: [], flying: false, kernels: nil, **)
            wheel = Geometry::Battlefield.apply_wheel(origin, heading, budget)
            wheeled = origin.merge(x: wheel[:x], y: wheel[:y], facing: wheel[:facing])
            remaining = wheel[:remaining]
            desired = Pathing.approach_desired(wheeled, remaining, wheel, goal_point, goal_unit, contact_id, heading)
            clearance = Pathing.furthest_clear_pose(
              origin, wheel, desired, obstacles,
              contact_id: contact_id,
              budget: budget,
              terrain: terrain,
              flying: flying,
              kernels: kernels
            )
            leftover = leftover_advance(wheel, clearance[:pose])
            plan = clearance.merge(
              wheel: wheel,
              turn: nil,
              desired: desired,
              maneuver: key,
              mv_spent_advance: leftover,
              mv_spent_march: 0.0
            )
            plan.merge(steps: Maneuvers.steps_for(plan))
          end

          def leftover_advance(wheel, pose)
            return 0.0 unless pose

            Geometry::Battlefield.distance_between({ x: wheel[:x], y: wheel[:y] }, pose)
          end
        end
      end
    end
  end
end
