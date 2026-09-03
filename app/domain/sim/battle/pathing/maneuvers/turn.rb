module Sim
  module Battle
    module Pathing
      module Maneuvers
        # In-place 90°: the old left/right flank becomes the new front. Costs half of
        # base MV; leftover may advance along the new facing. Not a wheel — the tray
        # does not swing through the old front arc.
        module Turn
          module_function

          def key
            :turn
          end

          def applies?(origin, heading, budget)
            return false if budget.to_f <= 0.05

            delta = Geometry::Battlefield.shortest_facing_delta(origin[:facing], heading)
            return false unless Geometry::Battlefield.turn_delta?(delta)

            Geometry::Battlefield.turn_cost(origin) <= budget.to_f + 0.0001
          end

          def simulate(origin:, heading:, budget:, goal_point:, goal_unit:, obstacles:, contact_id:, terrain: [], flying: false, kernels: nil, **)
            turn = Geometry::Battlefield.apply_turn(origin, heading, budget)
            empty = {
              pose: nil,
              truncated: true,
              blocker: nil,
              wheel: nil,
              turn: turn,
              desired: origin,
              maneuver: key,
              mv_spent_advance: 0.0,
              mv_spent_march: 0.0,
              steps: []
            }
            return empty if turn[:cost].to_f <= 0.05 || !turn[:completed]

            turned = Geometry::Battlefield.merge_footprint(origin, turn)
            remaining = turn[:remaining]
            desired = Pathing.approach_desired(turned, remaining, turn, goal_point, goal_unit, contact_id, heading)
            clearance = Pathing.furthest_clear_pose(
              origin, turn, desired, obstacles,
              contact_id: contact_id,
              budget: budget,
              terrain: terrain,
              flying: flying,
              kernels: kernels
            )
            spent = Maneuvers.pose_travel(turned, clearance[:pose])
            plan = clearance.merge(
              wheel: nil,
              turn: turn,
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
