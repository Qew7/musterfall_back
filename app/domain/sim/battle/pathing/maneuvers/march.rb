module Sim
  module Battle
    module Pathing
      module Maneuvers
        # March: double distance, straight along facing, only when no enemy
        # sits within 8" of the tray. Cannot mix with a wheel or turn.
        module March
          module_function

          def key
            :march
          end

          def multiplier
            Geometry::Battlefield::CONFIG[:march_multiplier].to_f
          end

          def applies?(origin, heading, budget, march_allowed:)
            return false unless march_allowed
            return false if budget.to_f <= 0.05

            Geometry::Battlefield.shortest_facing_delta(origin[:facing], heading).abs < 5.0
          end

          def simulate(origin:, heading:, budget:, goal_point:, goal_unit:, obstacles:, contact_id:, terrain: [], flying: false, kernels: nil, **)
            rate = multiplier
            travel_budget = budget.to_f * rate
            idle = {
              x: origin[:x].to_f,
              y: origin[:y].to_f,
              facing: Geometry::Battlefield.normalize_facing(origin[:facing]),
              cost: 0.0,
              remaining: travel_budget,
              completed: true,
              delta: 0.0,
              kind: :march
            }
            desired = Pathing.approach_desired(origin, travel_budget, idle, goal_point, goal_unit, contact_id, origin[:facing])
            clearance = Pathing.furthest_clear_pose(
              origin, idle, desired, obstacles,
              contact_id: contact_id,
              budget: travel_budget,
              terrain: terrain,
              flying: flying,
              kernels: kernels
            )
            travel = pose_travel(origin, clearance[:pose])
            cost = (clearance[:cost_spent] || travel) / rate
            plan = clearance.merge(
              wheel: idle,
              turn: nil,
              desired: desired,
              maneuver: key,
              mv_spent_advance: 0.0,
              mv_spent_march: cost,
              march_multiplier: rate
            )
            plan.merge(steps: Maneuvers.steps_for(plan))
          end

          def pose_travel(origin, pose)
            return 0.0 unless pose

            Geometry::Battlefield.distance_between(origin, pose)
          end
        end
      end
    end
  end
end
