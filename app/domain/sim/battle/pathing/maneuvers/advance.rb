module Sim
  module Battle
    module Pathing
      module Maneuvers
        # Normal-cost translation along current facing. Leftover MV after a wheel
        # or turn is also an advance — not a march.
        module Advance
          module_function

          def key
            :advance
          end

          def applies?(_origin, _heading, budget)
            budget.to_f > 0.05
          end

          def simulate(origin:, heading:, budget:, goal_point:, goal_unit:, obstacles:, contact_id:, terrain: [], flying: false, kernels: nil, **)
            idle = {
              x: origin[:x].to_f,
              y: origin[:y].to_f,
              facing: Geometry::Battlefield.normalize_facing(origin[:facing]),
              cost: 0.0,
              remaining: budget.to_f,
              completed: true,
              delta: 0.0,
              kind: :advance
            }
            desired = Pathing.approach_desired(origin, budget.to_f, idle, goal_point, goal_unit, contact_id, origin[:facing])
            clearance = Pathing.furthest_clear_pose(
              origin, idle, desired, obstacles,
              contact_id: contact_id,
              budget: budget,
              terrain: terrain,
              flying: flying,
              kernels: kernels
            )
            spent = Maneuvers.pose_travel(origin, clearance[:pose])
            plan = clearance.merge(
              wheel: idle,
              turn: nil,
              desired: desired,
              maneuver: key,
              mv_spent_advance: spent,
              mv_spent_march: 0.0
            )
            Maneuvers.finish_plan(plan)
          end
        end
      end
    end
  end
end
