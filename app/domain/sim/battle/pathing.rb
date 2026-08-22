module Sim
  module Battle
    module Pathing
      CONTACT = Geometry::Battlefield::CONFIG[:melee_contact_tolerance]
      CONTACT_SNAP = Geometry::Battlefield::CONFIG[:contact_snap]
      ENGAGE = CONTACT + CONTACT_SNAP
      ALIGNED_MARCH_DOT = 0.999
      ObstacleKernel = Struct.new(:id, :x, :y, :hw, :hd, :c, :s, :radius, :source)

      module_function

      # Units + impassable terrain OBBs for collision.
      def merge_obstacles(unit_obstacles, terrain = [])
        Array(unit_obstacles) + Geometry::Battlefield.impassable_obstacles(terrain)
      end

      # Pull a taut OBB thread to the claimed contact face, then follow it with
      # wheel / turn / advance / march. Extra kwargs are accepted for callers.
      def plan_approach(origin:, goal_point:, budget:, obstacles:, contact_id: nil, goal_unit: nil, bypass: true, allow_ally_bypass: false, approach_mode: :direct, terrain: [], flying: false, march_allowed: false, contact_slot: nil)
        world = Obstacles.coerce(obstacles)
        anchor = Thread.anchor(
          origin: origin,
          goal_point: goal_point,
          goal_unit: goal_unit,
          contact_id: contact_id,
          contact_slot: contact_slot,
          approach_mode: approach_mode
        )
        if contact_id && goal_unit
          face = Geometry::Battlefield.heading_to(origin, anchor)
          pose = origin.merge(x: anchor[:x], y: anchor[:y], facing: face)
          unless world.except(origin[:entity_id], contact_id).clear?(pose, contact_id: contact_id)
            anchor = world.contact_pose(origin, goal_unit, contact_id: contact_id) || anchor
          end
        end
        thread = Thread.pull(
          mover: origin,
          goal: anchor,
          world: world,
          contact_id: contact_id
        )
        Follow.along(
          origin: origin,
          thread: thread,
          budget: budget,
          goal_unit: goal_unit,
          world: world,
          obstacles: world,
          contact_id: contact_id,
          terrain: terrain,
          flying: flying,
          march_allowed: march_allowed
        )
      end

      # Waypoints off a defender's flank/rear face for slot-aware charges.
      def contact_slot_points(origin, defender, slot)
        slot_name = slot.to_s
        return [] if slot_name.empty? || slot_name == "front"

        dims = Geometry::Battlefield.unit_dimensions(defender)
        own = Geometry::Battlefield.unit_dimensions(origin)
        clearance = dims[:half_width] + own[:half_width] + CONTACT + 0.35
        forward = Geometry::Battlefield.facing_vector(defender[:facing])
        right = Geometry::Battlefield.right_vector(defender[:facing])

        points =
          case slot_name
          when "rear"
            depth = dims[:half_depth] + own[:half_depth] + CONTACT + 0.35
            [
              Geometry::Battlefield.clamp_battlefield_position(
                x: defender[:x] - (forward[:x] * depth),
                y: defender[:y] - (forward[:y] * depth),
                facing: 0
              )
            ]
          else # flank
            [
              Geometry::Battlefield.clamp_battlefield_position(
                x: defender[:x] + (right[:x] * clearance),
                y: defender[:y] + (right[:y] * clearance),
                facing: 0
              ),
              Geometry::Battlefield.clamp_battlefield_position(
                x: defender[:x] - (right[:x] * clearance),
                y: defender[:y] - (right[:y] * clearance),
                facing: 0
              )
            ]
          end
        points
      end

      # Run toward an edge (or preferred flee heading). Face the run direction.
      # Never orbit/slide around blockers — stop short or pick another straight edge.
      def plan_retreat(origin:, distance:, obstacles:, ally_ids: nil, preferred_heading: nil)
        ally_id_list = Array(ally_ids).compact
        edges = ordered_edges(origin)
        candidates = []
        world = Obstacles.coerce(obstacles)
        kernels = world.kernels

        if preferred_heading
          preferred = simulate_retreat(origin, preferred_heading, distance, world, kernels: kernels)
          candidates << preferred.merge(
            edge: "away",
            avoided: false,
            heading: preferred_heading,
            blocked_by_ally: friendly_blocker?(origin, preferred[:blocker], ally_id_list)
          )
        end

        edges.each do |edge|
          plan = simulate_retreat(origin, edge[:heading], distance, obstacles, kernels: kernels)
          next unless plan[:pose]

          candidates << plan.merge(
            edge: edge[:label],
            avoided: false,
            heading: edge[:heading],
            blocked_by_ally: friendly_blocker?(origin, plan[:blocker], ally_id_list)
          )
        end

        pick_best_retreat(candidates, origin, preferred_heading: preferred_heading)
      end

      def friendly_blocker?(origin, blocker, ally_id_list = [])
        return false unless blocker
        return true if Array(ally_id_list).include?(blocker[:entity_id])

        ally_blocker?(origin, blocker)
      end

      def active_units(combatants)
        combatants.select { |entry| entry[:current_health].to_i > 0 }
      end

      def first_blocker(projected, obstacles, contact_id: nil, origin: nil, kernels: nil)
        Obstacles.coerce(obstacles, kernels).first_blocker(projected, contact_id: contact_id)
      end

      def obstacle_kernels(obstacles)
        Obstacles.coerce(obstacles).kernels
      end

      def terrain_obstacle?(entry)
        entry && (entry[:obstacle_kind] == :terrain || entry[:obstacle_kind] == "terrain")
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
          # Thread already picked a clear pad (contact_pose). Recomputing
          # charge_destination here can land the tray on a lake beside the charge.
          engagement = if goal_point
            face = goal_point[:facing] || heading || wheeled[:facing]
            goal_point.merge(facing: face)
          else
            Geometry::Battlefield.charge_destination(wheeled, goal_unit, wheel[:facing])
          end
          distance = Geometry::Battlefield.distance_between(wheeled, engagement)
          return engagement if remaining + 0.05 >= distance

          return Geometry::Battlefield.move_along_facing(wheeled, remaining)
        end

        if goal_point
          vec = Geometry::Battlefield.facing_vector(wheeled[:facing])
          along = ((goal_point[:x].to_f - wheeled[:x].to_f) * vec[:x]) +
            ((goal_point[:y].to_f - wheeled[:y].to_f) * vec[:y])
          return wheeled if along <= 0.05

          return Geometry::Battlefield.move_along_facing(wheeled, [ remaining, along ].min)
        end

        Geometry::Battlefield.move_along_facing(wheeled, remaining)
      end

      def simulate_retreat(origin, heading, distance, obstacles, kernels: nil)
        world = Obstacles.coerce(obstacles, kernels)
        kernels = world.kernels
        # March along heading and face that way — no crab-walk with a mismatched footprint.
        run_facing = Geometry::Battlefield.normalize_facing(heading)
        desired = Geometry::Battlefield.move_along_facing(origin.merge(facing: run_facing), distance)
        steps = [ 8, (Geometry::Battlefield.distance_between(origin, desired) / 0.25).ceil ].max
        # Face the run immediately (free about-face). Start may already be in contact after melee;
        # only stepped poses are collision-tested so the unit can still peel away.
        last_clear = origin.merge(x: origin[:x].to_f, y: origin[:y].to_f, facing: run_facing)
        blocker = nil
        steps.times do |index|
          t = (index + 1).to_f / steps
          pose = origin.merge(
            x: origin[:x] + ((desired[:x] - origin[:x]) * t),
            y: origin[:y] + ((desired[:y] - origin[:y]) * t),
            facing: run_facing
          )
          hit = first_blocker(pose, obstacles, contact_id: nil, origin: origin, kernels: kernels)
          if hit
            blocker = hit
            break
          end

          last_clear = pose
        end

        truncated = !blocker.nil? || Geometry::Battlefield.distance_between(last_clear, desired) > 0.05
        { pose: last_clear, desired: desired, truncated: truncated, blocker: blocker, wheel: nil }
      end

      def furthest_clear_pose(origin, pivot, destination, obstacles, contact_id:, budget: nil, terrain: [], flying: false, kernels: nil)
        world = Obstacles.coerce(obstacles, kernels)
        kernels = world.kernels
        obstacles = world
        turning = pivot[:kind].to_s == "turn"
        wheel_samples = []
        last_clear = nil
        cost_spent = 0.0
        prev = origin.merge(x: origin[:x].to_f, y: origin[:y].to_f, facing: origin[:facing].to_f)

        if turning
          turned = Geometry::Battlefield.merge_footprint(origin, pivot)
          hit = first_blocker(turned, obstacles, contact_id: contact_id, origin: origin, kernels: kernels)
          if hit
            return { pose: nil, truncated: true, blocker: hit, cost_spent: pivot[:cost].to_f }
          end

          wheeled = turned
          last_clear = turned
          cost_spent = pivot[:cost].to_f
          prev = turned
        else
          if pivot[:delta].to_f.abs > 0.05
            steps = [ [ 8, (pivot[:delta].abs / 10).ceil ].max, 20 ].min
            steps.times do |index|
              progress = (index + 1).to_f / steps
              pose = Geometry::Battlefield.wheel_pose(origin, pivot[:delta] * progress)
              wheel_samples << origin.merge(x: pose[:x], y: pose[:y], facing: pose[:facing])
            end
          end

          wheeled = if wheel_samples.any?
            wheel_samples.last
          else
            origin.merge(x: pivot[:x], y: pivot[:y], facing: pivot[:facing])
          end
        end

        march_samples = []
        march_distance = Geometry::Battlefield.distance_between(wheeled, destination)
        facing_delta = Geometry::Battlefield.shortest_facing_delta(wheeled[:facing], destination[:facing]).abs
        if march_distance > 0.05 || facing_delta > 0.05
          steps = [ [ 8, (march_distance / 0.25).ceil ].max, 24 ].min
          steps.times do |index|
            t = (index + 1).to_f / steps
            march_samples << wheeled.merge(
              x: wheeled[:x] + ((destination[:x] - wheeled[:x]) * t),
              y: wheeled[:y] + ((destination[:y] - wheeled[:y]) * t),
              facing: destination[:facing]
            )
          end
        elsif wheel_samples.empty?
          march_samples << wheeled.merge(x: destination[:x], y: destination[:y], facing: destination[:facing])
        end

        march_collision = march_samples.empty? ||
          !aligned_translation?(wheeled, destination) ||
          !translation_clear?(wheeled, wheeled, destination, kernels, contact_id)
        samples = wheel_samples + march_samples
        wheel_count = wheel_samples.length

        blocker = nil
        budget_limit = budget.nil? ? nil : budget.to_f + 0.05

        samples.each_with_index do |pose, index|
          segment = Geometry::Battlefield.distance_between(prev, pose)
          multiplier = Geometry::Battlefield.move_cost_multiplier_at(pose, terrain, flying: flying)
          cost_spent += segment * multiplier
          if budget_limit && cost_spent > budget_limit
            break
          end

          if index < wheel_count || march_collision
            hit = first_blocker(pose, obstacles, contact_id: contact_id, origin: origin, kernels: kernels)
            if hit
              blocker = hit
              break
            end
          end

          last_clear = pose
          prev = pose
        end

        truncated = !blocker.nil? || (
          last_clear && (
            Geometry::Battlefield.distance_between(last_clear, destination) > 0.05 ||
            Geometry::Battlefield.shortest_facing_delta(last_clear[:facing], destination[:facing]).abs > 0.05
          )
        ) || (budget_limit && last_clear.nil? && samples.any?)

        # Budget exhausted mid-path without a unit/terrain blocker still counts as truncated.
        if budget_limit && last_clear && Geometry::Battlefield.distance_between(last_clear, destination) > 0.05
          truncated = true
        end

        { pose: last_clear, truncated: !!truncated, blocker: blocker, cost_spent: cost_spent }
      end

      def aligned_translation?(from, to)
        dx = to[:x].to_f - from[:x].to_f
        dy = to[:y].to_f - from[:y].to_f
        length = Geometry::Battlefield.distance_between(from, to)
        return true if length <= 0.05

        c, s = Geometry::Obb.trig(to[:facing])
        ((dx * c) + (dy * s)) >= (length * ALIGNED_MARCH_DOT)
      end

      def translation_clear?(mover, from, to, kernels, contact_id)
        Obstacles.coerce(nil, kernels).translation_clear?(mover, from, to, contact_id: contact_id)
      end

      def ally_blocker?(origin, blocker)
        return false unless blocker
        return false if terrain_obstacle?(blocker)

        !origin[:side_index].nil? && origin[:side_index] == blocker[:side_index]
      end

      def pick_best_retreat(candidates, origin, preferred_heading: nil)
        viable = candidates.select { |plan| plan[:pose] && meaningful_progress?(origin, plan[:pose]) }
        if viable.empty?
          # Prefer a turn-in-place toward the preferred/nearest run over a random stuck pose.
          return candidates.find { |plan| plan[:edge] == "away" } || candidates.first
        end

        viable.min_by { |plan| retreat_score(plan, origin, preferred_heading: preferred_heading) }
      end

      def retreat_score(plan, origin, preferred_heading: nil)
        pose = plan[:pose]
        heading_penalty = if preferred_heading
          Geometry::Battlefield.shortest_facing_delta(plan[:heading].to_f, preferred_heading).abs
        else
          0.0
        end
        ally_penalty = plan[:blocked_by_ally] ? 1 : 0
        [
          ally_penalty,
          heading_penalty,
          min_edge_distance(pose),
          -Geometry::Battlefield.distance_between(origin, pose)
        ]
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
