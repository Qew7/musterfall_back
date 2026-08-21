module Sim
  module Battle
    module Pathing
      # Declared movement primitives:
      #   wheel  — corner-pivot facing change
      #   turn   — 90° in place, old flank becomes the new front
      #   advance — normal-cost translation along facing
      #   march  — ×2 straight along facing when no enemy is within 8"
      module Maneuvers
        module_function

        def follow_segment(origin:, heading:, budget:, goal_point:, goal_unit:, obstacles:, contact_id:, terrain: [], flying: false, kernels: nil, march_allowed: false, finish: nil, allow_turn: true, **)
          space = Obstacles.coerce(obstacles, kernels)
          shared = {
            origin: origin,
            heading: heading,
            budget: budget,
            goal_point: goal_point,
            goal_unit: goal_unit,
            obstacles: space,
            contact_id: contact_id,
            terrain: terrain,
            flying: flying,
            kernels: space.kernels
          }
          if allow_turn && turn_for?(origin, heading, budget, finish, space, contact_id)
            Turn.simulate(**shared)
          elsif Wheel.applies?(origin, heading, budget)
            Wheel.simulate(**shared)
          elsif March.applies?(origin, heading, budget, march_allowed: march_allowed)
            March.simulate(**shared)
          else
            Advance.simulate(**shared)
          end
        end

        # Turn when the segment is a 90° reform, or when a wheel to this heading
        # cannot complete at the current frontage (arc cost or swing clearance).
        def turn_for?(origin, heading, budget, finish, space, contact_id)
          delta = Geometry::Battlefield.shortest_facing_delta(origin[:facing], heading)
          return false unless Geometry::Battlefield.turn_delta?(delta)
          return false if Geometry::Battlefield.turn_cost(origin) > budget.to_f + 0.0001
          return true if finish.nil? || Turn.applies?(origin, Geometry::Battlefield.heading_to(origin, finish), budget)
          !space.wheel_clear?(origin, heading, contact_id: contact_id)
        end

        def spent_mv(plan, origin)
          pivot = plan[:turn] || plan[:wheel]
          pivot_cost = pivot ? pivot[:cost].to_f : 0.0
          from = if pivot && pivot[:cost].to_f > 0.05
            { x: pivot[:x], y: pivot[:y] }
          else
            origin
          end
          pivot_cost + Geometry::Battlefield.distance_between(from, plan[:pose] || origin)
        end

        def steps_for(plan)
          steps = []
          if plan[:turn] && plan[:turn][:cost].to_f > 0.05
            steps << {
              kind: "turn",
              cost: plan[:turn][:cost].to_f,
              delta: plan[:turn][:delta].to_f,
              direction: plan[:turn][:delta].to_f.positive? ? "right" : "left"
            }
          elsif plan[:wheel] && plan[:wheel][:cost].to_f > 0.05
            steps << {
              kind: "wheel",
              cost: plan[:wheel][:cost].to_f,
              delta: plan[:wheel][:delta].to_f,
              direction: plan[:wheel][:delta].to_f.positive? ? "right" : "left"
            }
          end
          if plan[:maneuver] == :march && plan[:mv_spent_march].to_f > 0.05
            steps << { kind: "march", cost: plan[:mv_spent_march].to_f }
          elsif plan[:mv_spent_advance].to_f > 0.05
            steps << { kind: "advance", cost: plan[:mv_spent_advance].to_f }
          end
          steps
        end
      end
    end
  end
end
