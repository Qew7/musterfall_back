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
            kernels: space.kernels,
            march_allowed: march_allowed
          }
          if allow_turn && turn_for?(origin, heading, budget, finish, space, contact_id, march_allowed: march_allowed)
            Turn.simulate(**shared)
          elsif Wheel.applies?(origin, heading, budget)
            Wheel.simulate(**shared)
          elsif March.applies?(origin, heading, budget, march_allowed: march_allowed)
            March.simulate(**shared)
          else
            Advance.simulate(**shared)
          end
        end

        # Turn when the goal is a 90° reform, or when a wheel to this heading
        # cannot complete at the current frontage (arc cost or swing clearance).
        # `finish` must be the enemy/contact, not a wrap vertex beside the tray.
        def turn_for?(origin, heading, budget, finish, space, contact_id, march_allowed: false)
          return false if march_allowed

          delta = Geometry::Battlefield.shortest_facing_delta(origin[:facing], heading)
          return false unless Geometry::Battlefield.turn_delta?(delta)
          return false if Geometry::Battlefield.turn_cost(origin) > budget.to_f + 0.0001
          return true if finish.nil? || Turn.applies?(origin, Geometry::Battlefield.heading_to(origin, finish), budget)
          !space.wheel_clear?(origin, heading, contact_id: contact_id)
        end

        def spent_mv(plan, origin)
          spent = plan[:cost_spent].to_f
          return spent if spent > 0.05

          pivot = plan[:turn] || plan[:wheel]
          pivot_cost = pivot ? pivot[:cost].to_f : 0.0
          march_cost = plan[:mv_spent_march].to_f
          advance_cost = plan[:mv_spent_advance].to_f
          return pivot_cost + march_cost + advance_cost if march_cost > 0.05 || advance_cost > 0.05

          from = if pivot && pivot[:cost].to_f > 0.05
            { x: pivot[:x], y: pivot[:y] }
          else
            origin
          end
          pivot_cost + Geometry::Battlefield.distance_between(from, plan[:pose] || origin)
        end

        # Straight-line MV spent between two poses (0 when the pose is missing).
        # Shared by Advance / March / Turn, which all measure the same way.
        def pose_travel(origin, pose)
          return 0.0 unless pose

          Geometry::Battlefield.distance_between(origin, pose)
        end

        # Attach replay steps to a completed segment plan.
        def finish_plan(plan)
          plan.merge(steps: steps_for(plan))
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

        # Ordered poses for replay — one entry per declared primitive on a segment plan.
        def motion_entries_for(origin, plan)
          return [] unless plan && plan[:pose]

          entries = []
          pose = motion_pose(origin)

          turn = plan[:turn]
          if turn && turn[:cost].to_f > 0.05
            turned = Geometry::Battlefield.merge_footprint(origin, turn)
            entries << motion_entry("turn", pose, turned, turn)
            pose = motion_pose(turned)
          else
            wheel = plan[:wheel]
            if wheel && wheel[:cost].to_f > 0.05 && wheel[:delta].to_f.abs > 0.05
              wheeled = origin.merge(x: wheel[:x], y: wheel[:y], facing: wheel[:facing])
              entries << motion_entry("wheel", pose, wheeled, wheel)
              pose = motion_pose(wheeled)
            end
          end

          final = motion_pose(plan[:pose])
          if plan[:maneuver] == :march && plan[:mv_spent_march].to_f > 0.05
            entries << motion_entry("march", pose, final, cost: plan[:mv_spent_march].to_f) if motion_travel?(pose, final)
          elsif plan[:mv_spent_advance].to_f > 0.05
            entries << motion_entry("advance", pose, final, cost: plan[:mv_spent_advance].to_f) if motion_travel?(pose, final)
          end

          entries
        end

        def motion_pose(pose)
          return {} unless pose

          out = {
            x: pose[:x].to_f,
            y: pose[:y].to_f,
            facing: pose[:facing].to_f
          }
          out[:row] = pose[:row].to_s if pose[:row]
          out[:lane] = pose[:lane].to_s if pose[:lane]
          out
        end

        def motion_travel?(from, to)
          Geometry::Battlefield.distance_between(from, to) > 0.05 ||
            Geometry::Battlefield.shortest_facing_delta(from[:facing], to[:facing]).abs > 0.05
        end

        def motion_entry(kind, from_pose, to_pose, pivot = nil, cost: nil)
          entry = {
            kind: kind.to_s,
            from: motion_pose(from_pose),
            to: motion_pose(to_pose),
            cost: (cost || pivot&.dig(:cost)).to_f
          }
          if pivot && %w[turn wheel].include?(entry[:kind])
            entry[:delta] = pivot[:delta].to_f
            entry[:direction] = pivot[:delta].to_f.positive? ? "right" : "left"
          end
          entry
        end
      end
    end
  end
end
