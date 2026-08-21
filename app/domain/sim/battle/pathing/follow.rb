module Sim
  module Battle
    module Pathing
      # Walk a taut thread by composing declared maneuvers on each segment.
      module Follow
        module_function

        def along(origin:, thread:, budget:, goal_unit:, obstacles:, contact_id:, terrain: [], flying: false, kernels: nil, march_allowed: false, world: nil)
          space = Obstacles.coerce(world || obstacles, kernels)
          points = Array(thread[:points])
          return idle(origin, budget, thread) if points.length < 2
          return idle(origin, budget, thread) if points.length == 2 && same?(points[0], points[1])

          pose = origin
          remaining = budget.to_f
          steps = []
          advance = 0.0
          march = 0.0
          wheel = nil
          turn = nil
          desired = points.last
          last = nil
          maneuver = :advance
          multiplier = nil

          (0...(points.length - 1)).each do |index|
            break if remaining <= 0.05

            dest = points[index + 1]
            next if same?(pose, dest)

            last_segment = index == points.length - 2
            at_contact = thread[:complete] && last_segment
            heading = Geometry::Battlefield.heading_to(pose, dest)
            can_march = march_allowed && thread_straight?(thread) && last_segment
            plan = Maneuvers.follow_segment(
              origin: pose,
              heading: heading,
              budget: remaining,
              goal_point: dest,
              goal_unit: at_contact ? goal_unit : nil,
              obstacles: space,
              contact_id: contact_id,
              terrain: terrain,
              flying: flying,
              kernels: space.kernels,
              march_allowed: can_march,
              finish: points.last,
              allow_turn: index.zero?
            )
            break unless plan && plan[:pose]

            spent = plan[:cost_spent].to_f
            spent = Maneuvers.spent_mv(plan, pose) if spent <= 0.05
            pose = Geometry::Battlefield.merge_footprint(pose, plan[:pose])
            remaining = [ remaining - spent, 0.0 ].max
            steps.concat(Array(plan[:steps]))
            advance += plan[:mv_spent_advance].to_f
            march += plan[:mv_spent_march].to_f
            wheel = plan[:wheel] if plan.dig(:wheel, :cost).to_f > 0.05 && wheel.nil?
            turn = plan[:turn] if plan.dig(:turn, :cost).to_f > 0.05
            desired = plan[:desired] || dest
            last = plan
            maneuver = plan[:maneuver]
            multiplier = plan[:march_multiplier] if plan[:march_multiplier]
            reached = Geometry::Battlefield.distance_between(pose, dest) <= 0.2
            next unless plan[:truncated] && !reached

            hit = plan[:blocker]
            contact_hit = contact_id && hit && hit[:entity_id] == contact_id
            nxt = points[index + 2]
            finish = points.last
            receding = nxt.nil? ||
              Geometry::Battlefield.distance_between(nxt, finish) >=
                Geometry::Battlefield.distance_between(pose, finish) - 0.05
            break if contact_hit || remaining <= 0.5 || spent <= 0.05 || receding
          end

          wrapped = Array(thread[:wrapped])
          blocker = last && last[:blocker]
          heading = Geometry::Battlefield.heading_to(origin, points[1] || origin)

          {
            pose: pose,
            truncated: !blocker.nil?,
            blocker: blocker,
            cost_spent: budget.to_f - remaining,
            wheel: wheel || idle_pivot(origin, budget),
            turn: turn,
            desired: desired,
            maneuver: maneuver,
            mv_spent_advance: advance,
            mv_spent_march: march,
            march_multiplier: multiplier,
            steps: steps,
            avoided: wrapped.any? && points.length > 2,
            heading: heading,
            blocked_by_ally: false,
            thread: points
          }
        end

        def thread_straight?(thread)
          Array(thread[:points]).length <= 2 && Array(thread[:wrapped]).empty?
        end

        def idle(origin, budget, thread)
          {
            pose: origin,
            truncated: false,
            blocker: nil,
            cost_spent: 0.0,
            wheel: idle_pivot(origin, budget),
            turn: nil,
            desired: origin,
            maneuver: :advance,
            mv_spent_advance: 0.0,
            mv_spent_march: 0.0,
            march_multiplier: nil,
            steps: [],
            avoided: false,
            heading: origin[:facing],
            blocked_by_ally: false,
            thread: Array(thread[:points])
          }
        end

        def idle_pivot(origin, budget)
          {
            x: origin[:x].to_f,
            y: origin[:y].to_f,
            facing: Geometry::Battlefield.normalize_facing(origin[:facing]),
            cost: 0.0,
            remaining: budget.to_f,
            completed: true,
            delta: 0.0,
            kind: :advance
          }
        end

        def same?(left, right)
          Geometry::Battlefield.distance_between(left, right) <= 0.05
        end
      end
    end
  end
end
