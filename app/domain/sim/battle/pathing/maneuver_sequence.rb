module Sim
  module Battle
    module Pathing
      # Express a clear route as declared maneuvers.
      module ManeuverSequence
        module_function

        def along(origin:, route:, budget:, goal_unit:, obstacles:, contact_id:, terrain: [], flying: false, kernels: nil, march_allowed: false, world: nil)
          space = Obstacles.coerce(world || obstacles, kernels)
          points = Array(route[:points])
          return idle(origin, budget, route) if points.length < 2
          return idle(origin, budget, route) if points.length == 2 && same?(points[0], points[1])

          pose = origin
          remaining = budget.to_f
          steps = []
          motion_sequence = []
          advance = 0.0
          march = 0.0
          wheel_spent = 0.0
          turn_spent = 0.0
          wheel = nil
          turn = nil
          desired = points.last
          last = nil
          maneuver = :advance
          multiplier = nil
          goal = route[:complete] ? points.last : goal_unit

          (0...(points.length - 1)).each do |index|
            break if remaining <= 0.05

            dest = points[index + 1]
            next if same?(pose, dest)

            last_segment = index == points.length - 2
            at_contact = route[:complete] && last_segment
            heading = Geometry::Battlefield.heading_to(pose, dest)
            can_march = march_allowed && straight_route?(route) && last_segment
            plan = Maneuvers.plan_segment(
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
              finish: goal || points.last,
              allow_turn: last.nil?
            )
            break unless plan && plan[:pose]
            if index.zero? &&
                plan[:maneuver] == :wheel &&
                plan[:truncated] &&
                Pathing.terrain_obstacle?(plan[:blocker]) &&
                Geometry::Battlefield.distance_between(origin, plan[:pose]) <= 0.5
              break
            end

            segment_origin = pose
            spent = plan[:cost_spent].to_f
            spent = Maneuvers.spent_mv(plan, pose) if spent <= 0.05
            motion_sequence.concat(Maneuvers.motion_entries_for(segment_origin, plan))
            pose = Geometry::Battlefield.merge_footprint(pose, plan[:pose])
            remaining = [ remaining - spent, 0.0 ].max
            steps.concat(Array(plan[:steps]))
            segment_wheel = plan.dig(:wheel, :cost).to_f
            segment_turn = plan.dig(:turn, :cost).to_f
            translation_spent = [ spent - segment_wheel - segment_turn, 0.0 ].max
            advance += translation_spent if plan[:mv_spent_advance].to_f > 0.05
            march += translation_spent if plan[:mv_spent_march].to_f > 0.05
            wheel_spent += segment_wheel
            turn_spent += segment_turn
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

          if same?(pose, origin) && remaining > 0.5
            reformed = reform_idle(
              origin: origin,
              points: points,
              budget: remaining,
              space: space,
              contact_id: contact_id,
              terrain: terrain,
              flying: flying
            )
            if reformed && reformed[:pose]
              pose = Geometry::Battlefield.merge_footprint(origin, reformed[:pose])
              spent = reformed[:cost_spent].to_f
              spent = Maneuvers.spent_mv(reformed, origin) if spent <= 0.05
              remaining = [ remaining - spent, 0.0 ].max
              motion_sequence = Maneuvers.motion_entries_for(origin, reformed)
              steps = Array(reformed[:steps])
              wheel_spent = reformed.dig(:wheel, :cost).to_f
              turn_spent = reformed.dig(:turn, :cost).to_f
              translation_spent = [ spent - wheel_spent - turn_spent, 0.0 ].max
              advance = reformed[:mv_spent_advance].to_f > 0.05 ? translation_spent : 0.0
              march = reformed[:mv_spent_march].to_f > 0.05 ? translation_spent : 0.0
              wheel = reformed[:wheel]
              turn = reformed[:turn]
              desired = reformed[:desired] || desired
              last = reformed
              maneuver = reformed[:maneuver]
            end
          end

          blocker = last && last[:blocker]
          heading = Geometry::Battlefield.heading_to(origin, points[1] || origin)
          if goal_unit && points.length == 2
            before = Geometry::Battlefield.distance_between_units(origin, goal_unit)
            after = Geometry::Battlefield.distance_between_units(
              Geometry::Battlefield.merge_footprint(origin, pose),
              goal_unit
            )
            return idle(origin, budget, route) if before <= budget.to_f + Pathing::ENGAGE &&
              after > before + 0.05
          end

          motion_sequence = Maneuvers.compact_motion_entries(motion_sequence)
          motion_sequence = Maneuvers.trim_motion_entries(motion_sequence, budget, origin)
          if motion_sequence.any?
            pose = Geometry::Battlefield.merge_footprint(origin, motion_sequence.last[:to])
          end
          grouped = motion_sequence.group_by { |motion| motion[:kind].to_s }
          wheel_spent = Array(grouped["wheel"]).sum { |motion| motion[:cost].to_f }
          turn_spent = Array(grouped["turn"]).sum { |motion| motion[:cost].to_f }
          advance = Array(grouped["advance"]).sum { |motion| motion[:cost].to_f }
          march = Array(grouped["march"]).sum { |motion| motion[:cost].to_f }
          total_spent = wheel_spent + turn_spent + advance + march
          steps = motion_sequence.map { |motion|
            motion.slice(:kind, :cost, :delta, :direction)
          }

          {
            pose: pose,
            truncated: !blocker.nil?,
            blocker: blocker,
            cost_spent: total_spent,
            wheel: wheel || idle_pivot(origin, budget),
            turn: turn,
            desired: desired,
            maneuver: maneuver,
            mv_spent_advance: advance,
            mv_spent_march: march,
            mv_spent_wheel: wheel_spent,
            mv_spent_turn: turn_spent,
            march_multiplier: multiplier,
            steps: steps,
            motion_sequence: motion_sequence,
            heading: heading,
            blocked_by_ally: false
          }
        end

        def straight_route?(route)
          Array(route[:points]).length <= 2
        end

        # ponytail: CONTACT-kissing trays idle when every wheel clips the lake and
        # Advance walks into it. Reform 90° toward the wrap hop only then — live
        # contact_align / jam closing must keep their pose.
        def reform_idle(origin:, points:, budget:, space:, contact_id:, terrain:, flying:)
          return nil unless points.length > 2

          probe = Geometry::Battlefield.move_along_facing(origin, 0.5)
          hit = space.first_blocker(origin.merge(x: probe[:x], y: probe[:y]), contact_id: contact_id)
          return nil unless hit && Pathing.terrain_obstacle?(hit)

          dest = points[1]
          nxt = points[2]
          heading = Geometry::Battlefield.heading_to(origin, dest)
          if nxt &&
              Geometry::Battlefield.shortest_facing_delta(heading, Geometry::Battlefield.heading_to(origin, nxt)).abs >= 90.0
            heading = Geometry::Battlefield.heading_to(origin, nxt)
          end
          delta = Geometry::Battlefield.shortest_facing_delta(origin[:facing], heading)
          return nil unless delta.abs > 45.0

          snapped = Geometry::Battlefield.normalize_facing(
            origin[:facing].to_f + (delta.positive? ? 90.0 : -90.0)
          )
          plan = Maneuvers::Turn.simulate(
            origin: origin,
            heading: snapped,
            budget: budget,
            goal_point: nxt || dest,
            goal_unit: nil,
            obstacles: space,
            contact_id: contact_id,
            terrain: terrain,
            flying: flying
          )
          return nil unless plan && plan[:pose]
          return nil if same?(plan[:pose], origin) &&
            Geometry::Battlefield.shortest_facing_delta(origin[:facing], plan[:pose][:facing]).abs <= 0.05

          plan
        end

        def idle(origin, budget, _route)
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
            mv_spent_wheel: 0.0,
            mv_spent_turn: 0.0,
            march_multiplier: nil,
            steps: [],
            motion_sequence: [],
            heading: origin[:facing],
            blocked_by_ally: false
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
