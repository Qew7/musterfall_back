module Sim
  module Battle
    module Pathing
      CONTACT = Geometry::Battlefield::CONFIG[:melee_contact_tolerance]
      BYPASS_HEADING_OFFSETS = [ 45, -45, 90, -90 ].freeze

      module_function

      # Wheel + march toward a goal. Bypass only enemy blockers — allies are a traffic jam, not a detour.
      # Set bypass: false for cheap reposition probes (direct line only).
      def plan_approach(origin:, goal_point:, budget:, obstacles:, contact_id: nil, goal_unit: nil, bypass: true)
        direct_heading = Geometry::Battlefield.heading_to(origin, goal_point)
        direct = simulate_approach(
          origin: origin,
          heading: direct_heading,
          budget: budget,
          goal_point: goal_point,
          goal_unit: goal_unit,
          obstacles: obstacles,
          contact_id: contact_id
        )
        base = direct.merge(avoided: false, heading: direct_heading, blocked_by_ally: false)
        return base unless bypass
        return base unless worth_bypassing?(direct, origin)

        # Friendly column ahead: hold the direct line (creep / face), never circle around allies.
        if ally_blocker?(origin, direct[:blocker])
          return base.merge(blocked_by_ally: true)
        end

        candidates = [ base ]
        bypass_headings_for(origin, direct_heading, direct[:blocker]).each do |heading|
          plan = simulate_approach(
            origin: origin,
            heading: heading,
            budget: budget,
            goal_point: goal_point,
            goal_unit: goal_unit,
            obstacles: obstacles,
            contact_id: contact_id
          )
          next unless plan[:pose]

          candidates << plan.merge(avoided: true, heading: heading, blocked_by_ally: false)
        end

        if direct[:blocker]
          flank_points(origin, direct[:blocker]).each do |point|
            heading = Geometry::Battlefield.heading_to(origin, point)
            plan = simulate_approach(
              origin: origin,
              heading: heading,
              budget: budget,
              goal_point: point,
              goal_unit: nil,
              obstacles: obstacles,
              contact_id: nil
            )
            next unless plan[:pose]

            candidates << plan.merge(avoided: true, heading: heading, blocked_by_ally: false)
          end
        end

        pick_best_approach(candidates, origin, goal_point, goal_unit)
      end

      # Translate toward a map edge. Do not slide around friendly blockers — stop or pick another edge.
      def plan_retreat(origin:, distance:, obstacles:, ally_ids: nil)
        ally_id_list = Array(ally_ids).compact
        edges = ordered_edges(origin)
        direct_edge = edges.first
        direct = simulate_retreat(origin, direct_edge[:heading], distance, obstacles)
          .merge(edge: direct_edge[:label], avoided: false, heading: direct_edge[:heading], blocked_by_ally: false)

        if friendly_blocker?(origin, direct[:blocker], ally_id_list)
          return retreat_without_friendly_slide(
            origin: origin,
            distance: distance,
            obstacles: obstacles,
            edges: edges,
            direct: direct.merge(blocked_by_ally: true),
            ally_id_list: ally_id_list
          )
        end

        return direct unless worth_bypassing?(direct, origin)

        candidates = [ direct ]
        edges.each do |edge|
          ([ edge[:heading] ] + BYPASS_HEADING_OFFSETS.map { |offset| Geometry::Battlefield.normalize_facing(edge[:heading] + offset) }).uniq.each do |heading|
            next if edge[:label] == direct_edge[:label] && heading == direct_edge[:heading]

            plan = simulate_retreat(origin, heading, distance, obstacles)
            next unless plan[:pose]
            next if friendly_blocker?(origin, plan[:blocker], ally_id_list)

            candidates << plan.merge(edge: edge[:label], avoided: true, heading: heading, blocked_by_ally: false)
          end
        end

        if direct[:blocker] && !friendly_blocker?(origin, direct[:blocker], ally_id_list)
          flank_points(origin, direct[:blocker]).each do |point|
            heading = Geometry::Battlefield.heading_to(origin, point)
            plan = simulate_retreat(origin, heading, distance, obstacles)
            next unless plan[:pose]
            next if friendly_blocker?(origin, plan[:blocker], ally_id_list)

            candidates << plan.merge(edge: direct_edge[:label], avoided: true, heading: heading, blocked_by_ally: false)
          end
        end

        pick_best_retreat(candidates, origin)
      end

      # Ally blocked the nearest edge: may switch to another edge's straight run, never orbit the friend.
      def retreat_without_friendly_slide(origin:, distance:, obstacles:, edges:, direct:, ally_id_list:)
        candidates = [ direct ]
        edges.drop(1).each do |edge|
          plan = simulate_retreat(origin, edge[:heading], distance, obstacles)
          next unless plan[:pose]
          next unless meaningful_progress?(origin, plan[:pose])

          candidates << plan.merge(
            edge: edge[:label],
            avoided: false,
            heading: edge[:heading],
            blocked_by_ally: friendly_blocker?(origin, plan[:blocker], ally_id_list)
          )
        end
        pick_best_retreat(candidates, origin)
      end

      def friendly_blocker?(origin, blocker, ally_id_list = [])
        return false unless blocker
        return true if Array(ally_id_list).include?(blocker[:entity_id])

        ally_blocker?(origin, blocker)
      end

      def active_units(combatants)
        combatants.select { |entry| entry[:current_health].to_i > 0 }
      end

      def first_blocker(projected, obstacles, contact_id: nil, origin: nil)
        px = projected[:x].to_f
        py = projected[:y].to_f
        pr = rough_footprint_radius(projected) + CONTACT

        obstacles.find do |entry|
          next false if entry[:entity_id] == projected[:entity_id]
          next false if entry[:current_health].to_i <= 0
          next false if entry[:x].nil? || entry[:y].nil?

          # Cheap center reject before expensive OBB distance.
          dx = px - entry[:x].to_f
          dy = py - entry[:y].to_f
          reach = pr + rough_footprint_radius(entry)
          next false if ((dx * dx) + (dy * dy)) > (reach * reach)

          other = entry.merge(facing: entry[:facing].to_f)
          dist = Geometry::Battlefield.distance_between_units(projected, other)
          if contact_id && entry[:entity_id] == contact_id
            Geometry::Battlefield.rectangles_overlap?(projected, other)
          else
            dist < CONTACT
          end
        end
      end

      def rough_footprint_radius(unit)
        hw = (unit[:base_width] || unit[:width] || 1).to_f * 0.5
        hd = (unit[:base_depth] || unit[:depth] || 1).to_f * 0.5
        Math.hypot(hw, hd)
      end

      def simulate_approach(origin:, heading:, budget:, goal_point:, goal_unit:, obstacles:, contact_id:)
        wheeled_plan = simulate_wheeled_approach(
          origin: origin,
          heading: heading,
          budget: budget,
          goal_point: goal_point,
          goal_unit: goal_unit,
          obstacles: obstacles,
          contact_id: contact_id
        )
        return wheeled_plan if meaningful_progress?(origin, wheeled_plan[:pose])

        # Tiny corrective wheels on wide formations often clip allies behind the unit.
        # Fall back to a straight march on the current facing so columns can still advance.
        straight_plan = simulate_straight_march(
          origin: origin,
          budget: budget,
          goal_point: goal_point,
          goal_unit: goal_unit,
          obstacles: obstacles,
          contact_id: contact_id
        )
        return straight_plan if meaningful_progress?(origin, straight_plan[:pose])

        wheeled_plan[:pose] ? wheeled_plan : straight_plan
      end

      def simulate_wheeled_approach(origin:, heading:, budget:, goal_point:, goal_unit:, obstacles:, contact_id:)
        wheel = Geometry::Battlefield.apply_wheel(origin, heading, budget)
        wheeled = origin.merge(x: wheel[:x], y: wheel[:y], facing: wheel[:facing])
        remaining = wheel[:remaining]
        desired = approach_desired(wheeled, remaining, wheel, goal_point, goal_unit, contact_id, heading)
        clearance = furthest_clear_pose(origin, wheel, desired, obstacles, contact_id: contact_id)
        clearance.merge(wheel: wheel, desired: desired)
      end

      def simulate_straight_march(origin:, budget:, goal_point:, goal_unit:, obstacles:, contact_id:)
        idle_wheel = {
          x: origin[:x].to_f,
          y: origin[:y].to_f,
          facing: Geometry::Battlefield.normalize_facing(origin[:facing]),
          cost: 0.0,
          remaining: budget.to_f,
          completed: true,
          delta: 0.0
        }
        desired = approach_desired(origin, budget.to_f, idle_wheel, goal_point, goal_unit, contact_id, origin[:facing])
        clearance = furthest_clear_pose(origin, idle_wheel, desired, obstacles, contact_id: contact_id)
        clearance.merge(wheel: idle_wheel, desired: desired)
      end

      def meaningful_progress?(origin, pose)
        return false unless pose

        Geometry::Battlefield.distance_between(origin, pose) > 0.05 ||
          Geometry::Battlefield.shortest_facing_delta(origin[:facing], pose[:facing]).abs > 0.05
      end

      def approach_desired(wheeled, remaining, wheel, goal_point, goal_unit, contact_id, heading)
        return wheeled if remaining <= 0.05

        toward_contact = contact_id && goal_unit &&
          Geometry::Battlefield.shortest_facing_delta(wheel[:facing], heading).abs < 0.05 &&
          wheel[:completed]

        if toward_contact
          engagement = Geometry::Battlefield.charge_destination(wheeled, goal_unit, wheel[:facing])
          distance = Geometry::Battlefield.distance_between(wheeled, engagement)
          return engagement if remaining + 0.05 >= distance

          return Geometry::Battlefield.move_along_facing(wheeled, remaining)
        end

        # Non-contact (reposition): stop at the goal instead of burning leftover MV past it.
        # That leftover is needed for a final face-toward-target wheel.
        if goal_point && Geometry::Battlefield.shortest_facing_delta(wheeled[:facing], heading).abs < 5.0
          dist = Geometry::Battlefield.distance_between(wheeled, goal_point)
          return Geometry::Battlefield.move_along_facing(wheeled, [ remaining, dist ].min)
        end

        Geometry::Battlefield.move_along_facing(wheeled, remaining)
      end

      def simulate_retreat(origin, heading, distance, obstacles)
        # Translate along the chosen run heading; keep the unit's current facing for the footprint.
        desired = Geometry::Battlefield.move_along_facing(origin.merge(facing: heading), distance)
          .merge(facing: origin[:facing])
        steps = [ 8, (Geometry::Battlefield.distance_between(origin, desired) / 0.25).ceil ].max
        last_clear = { x: origin[:x].to_f, y: origin[:y].to_f, facing: origin[:facing] }
        blocker = nil
        steps.times do |index|
          t = (index + 1).to_f / steps
          pose = origin.merge(
            x: origin[:x] + ((desired[:x] - origin[:x]) * t),
            y: origin[:y] + ((desired[:y] - origin[:y]) * t),
            facing: origin[:facing]
          )
          hit = first_blocker(pose, obstacles, contact_id: nil, origin: origin)
          if hit
            blocker = hit
            break
          end

          last_clear = pose
        end

        truncated = !blocker.nil? || Geometry::Battlefield.distance_between(last_clear, desired) > 0.05
        { pose: last_clear, desired: desired, truncated: truncated, blocker: blocker, wheel: nil }
      end

      def furthest_clear_pose(origin, wheel, destination, obstacles, contact_id:)
        samples = []
        if wheel[:delta].to_f.abs > 0.05
          steps = [ [ 8, (wheel[:delta].abs / 10).ceil ].max, 20 ].min
          steps.times do |index|
            progress = (index + 1).to_f / steps
            pose = Geometry::Battlefield.wheel_pose(origin, wheel[:delta] * progress)
            samples << origin.merge(x: pose[:x], y: pose[:y], facing: pose[:facing])
          end
        end

        wheeled = if samples.any?
          samples.last
        else
          origin.merge(x: wheel[:x], y: wheel[:y], facing: wheel[:facing])
        end

        march_distance = Geometry::Battlefield.distance_between(wheeled, destination)
        facing_delta = Geometry::Battlefield.shortest_facing_delta(wheeled[:facing], destination[:facing]).abs
        if march_distance > 0.05 || facing_delta > 0.05
          steps = [ [ 8, (march_distance / 0.25).ceil ].max, 24 ].min
          steps.times do |index|
            t = (index + 1).to_f / steps
            samples << wheeled.merge(
              x: wheeled[:x] + ((destination[:x] - wheeled[:x]) * t),
              y: wheeled[:y] + ((destination[:y] - wheeled[:y]) * t),
              facing: destination[:facing]
            )
          end
        elsif samples.empty?
          samples << wheeled.merge(x: destination[:x], y: destination[:y], facing: destination[:facing])
        end

        last_clear = nil
        blocker = nil
        samples.each do |pose|
          hit = first_blocker(pose, obstacles, contact_id: contact_id, origin: origin)
          if hit
            blocker = hit
            break
          end

          last_clear = pose
        end

        truncated = !blocker.nil? || (
          last_clear && (
            Geometry::Battlefield.distance_between(last_clear, destination) > 0.05 ||
            Geometry::Battlefield.shortest_facing_delta(last_clear[:facing], destination[:facing]).abs > 0.05
          )
        )

        { pose: last_clear, truncated: !!truncated, blocker: blocker }
      end

      def worth_bypassing?(plan, origin)
        return true if plan[:blocker] && !meaningful_progress?(origin, plan[:pose])
        return false unless plan[:truncated] && plan[:blocker]
        return true unless plan[:pose]

        Geometry::Battlefield.distance_between(origin, plan[:pose]) < (origin[:movement] || 3).to_f * 0.85
      end

      def ally_blocker?(origin, blocker)
        return false unless blocker

        !origin[:side_index].nil? && origin[:side_index] == blocker[:side_index]
      end

      def bypass_headings_for(origin, direct_heading, blocker)
        headings = BYPASS_HEADING_OFFSETS.map { |offset| Geometry::Battlefield.normalize_facing(direct_heading + offset) }
        if blocker
          flank_points(origin, blocker).each do |point|
            headings << Geometry::Battlefield.heading_to(origin, point)
          end
        end
        headings.uniq
      end

      def flank_points(origin, blocker)
        dims = Geometry::Battlefield.unit_dimensions(origin)
        other = Geometry::Battlefield.unit_dimensions(blocker)
        clearance = dims[:half_width] + other[:half_width] + CONTACT + 0.35
        dx = blocker[:x].to_f - origin[:x].to_f
        dy = blocker[:y].to_f - origin[:y].to_f
        length = Math.hypot(dx, dy)
        return [] if length < 0.001

        nx = -dy / length
        ny = dx / length
        [
          Geometry::Battlefield.clamp_battlefield_position(x: blocker[:x] + (nx * clearance), y: blocker[:y] + (ny * clearance), facing: 0),
          Geometry::Battlefield.clamp_battlefield_position(x: blocker[:x] - (nx * clearance), y: blocker[:y] - (ny * clearance), facing: 0)
        ]
      end

      def pick_best_approach(candidates, origin, goal_point, goal_unit)
        viable = candidates.select { |plan| meaningful_progress?(origin, plan[:pose]) }
        return (candidates.find { |plan| !plan[:avoided] } || candidates.first).merge(avoided: false) if viable.empty?

        best = viable.min_by { |plan| approach_score(plan[:pose], origin, goal_point, goal_unit) }
        direct = candidates.find { |plan| !plan[:avoided] } || candidates.first
        if meaningful_progress?(origin, direct[:pose]) &&
            score_at_least?(approach_score(best[:pose], origin, goal_point, goal_unit), approach_score(direct[:pose], origin, goal_point, goal_unit))
          return direct
        end

        best
      end

      def approach_score(pose, origin, goal_point, goal_unit)
        goal_distance = if goal_unit
          Geometry::Battlefield.distance_between_units(pose, goal_unit)
        else
          Geometry::Battlefield.distance_between(pose, goal_point)
        end
        [ goal_distance, -Geometry::Battlefield.distance_between(origin, pose) ]
      end

      def pick_best_retreat(candidates, origin)
        viable = candidates.select { |plan| plan[:pose] }
        return candidates.first if viable.empty?

        best = viable.min_by { |plan| retreat_score(plan[:pose], origin) }
        direct = candidates.find { |plan| !plan[:avoided] } || candidates.first
        if direct[:pose] && score_at_least?(retreat_score(best[:pose], origin), retreat_score(direct[:pose], origin))
          return direct
        end

        best
      end

      def retreat_score(pose, origin)
        [ min_edge_distance(pose), -Geometry::Battlefield.distance_between(origin, pose) ]
      end

      def score_at_least?(left, right)
        (left <=> right) >= 0
      end

      def min_edge_distance(pose)
        width = Geometry::Battlefield::CONFIG[:width] - 1
        height = Geometry::Battlefield::CONFIG[:height] - 1
        [
          pose[:x].to_f,
          width - pose[:x].to_f,
          pose[:y].to_f,
          height - pose[:y].to_f
        ].min
      end

      def ordered_edges(origin)
        width = Geometry::Battlefield::CONFIG[:width] - 1
        height = Geometry::Battlefield::CONFIG[:height] - 1
        [
          { label: "west", distance: origin[:x].to_f, point: { x: 0, y: origin[:y] } },
          { label: "east", distance: width - origin[:x].to_f, point: { x: width, y: origin[:y] } },
          { label: "north", distance: origin[:y].to_f, point: { x: origin[:x], y: 0 } },
          { label: "south", distance: height - origin[:y].to_f, point: { x: origin[:x], y: height } }
        ].sort_by { |edge| edge[:distance] }
          .map { |edge| edge.merge(heading: Geometry::Battlefield.heading_to(origin, edge[:point])) }
      end
    end
  end
end
