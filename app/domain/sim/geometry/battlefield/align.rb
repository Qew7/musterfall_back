module Sim
  module Geometry
    module Battlefield
      module Align
        # Free post-contact align: hinge on the contact feature (often the enemy tray corner on our front),
        # not a WHFB formation-front pivot. Prefer the rotation with more frontage in contact / free side.
        def contact_pivot_point(attacker, defender)
          best = nil
          unit_corners(defender).each do |corner|
            unit_edges(attacker).each do |edge_start, edge_end|
              dist = distance_point_to_segment(corner, edge_start, edge_end)
              next if best && dist >= best[:dist] - 0.0001

              # Hinge on the enemy corner when it is the contact feature.
              best = { dist: dist, point: { x: corner[:x].to_f, y: corner[:y].to_f }, source: :defender_corner }
            end
          end
          unit_corners(attacker).each do |corner|
            unit_edges(defender).each do |edge_start, edge_end|
              dist = distance_point_to_segment(corner, edge_start, edge_end)
              next if best && dist > best[:dist] + 0.0001
              next if best && dist >= best[:dist] - 0.0001 && best[:source] == :defender_corner

              best = { dist: dist, point: { x: corner[:x].to_f, y: corner[:y].to_f }, source: :attacker_corner }
            end
          end
          best && best[:point]
        end

        def rotate_unit_around_point(unit, pivot, delta_degrees)
          radians = delta_degrees * (Math::PI / 180.0)
          cos_a = Math.cos(radians)
          sin_a = Math.sin(radians)
          vx = unit[:x].to_f - pivot[:x].to_f
          vy = unit[:y].to_f - pivot[:y].to_f
          clamp_battlefield_position(
            x: pivot[:x] + (vx * cos_a) - (vy * sin_a),
            y: pivot[:y] + (vx * sin_a) + (vy * cos_a),
            facing: normalize_facing(unit[:facing].to_f + delta_degrees)
          ).merge(unit.except(:x, :y, :facing))
        end

        # Overlap of the two footprints along the attacker's front axis (proxy for models in contact).
        def front_contact_span(attacker, defender)
          axis = right_vector(attacker[:facing])
          left = project_unit_onto_axis(attacker, axis)
          right = project_unit_onto_axis(defender, axis)
          [ 0.0, [ left[:max], right[:max] ].min - [ left[:min], right[:min] ].max ].max
        end

        # Friends farther than our tray's long side cannot intersect a free-align wheel,
        # so they must not bias free_side scoring (Battle 33: distant boyz forced a 330° swing).
        def idle_ally_proximity_limit(attacker)
          dims = unit_dimensions(attacker)
          [ dims[:half_width] * 2.0, dims[:half_depth] * 2.0 ].max
        end

        def idle_ally_obstacles(attacker, defender, obstacles)
          reach = idle_ally_proximity_limit(attacker)
          Array(obstacles).select do |obs|
            next false if obs[:entity_id] == attacker[:entity_id] || obs[:entity_id] == defender[:entity_id]
            next false if obs[:current_health].to_i <= 0
            next false if !attacker[:side_index].nil? && !obs[:side_index].nil? && obs[:side_index] != attacker[:side_index]
            # Friend not locked in contact with this defender — still a physical block for align.
            next false if distance_between_units(obs, defender) <= (CONFIG[:melee_contact_tolerance] + CONFIG[:contact_snap])
            # Only allies close enough to clip our wheel matter for free_side / short-arc checks.
            next false if distance_between_units(attacker, obs) > reach

            true
          end
        end

        def align_direction_blocked_by_idle_ally?(origin, pivot, delta, defender, idle_allies)
          return false if idle_allies.empty? || delta.abs < 0.05

          contact = CONFIG[:melee_contact_tolerance]
          steps = [ 8, (delta.abs / 10).ceil ].max
          steps = [ steps, 24 ].min
          steps.times do |index|
            progress = (index + 1).to_f / steps
            candidate = rotate_unit_around_point(origin, pivot, delta * progress)
            hit = idle_allies.any? do |ally|
              rectangles_overlap?(candidate, ally) || distance_between_units(candidate, ally) < contact
            end
            return true if hit
          end
          false
        end

        def align_fronts_pose(attacker, defender, obstacles: [])
          desired_facing = facing_into_contact_face(attacker, defender)
          start = attacker.merge(x: attacker[:x].to_f, y: attacker[:y].to_f, facing: normalize_facing(attacker[:facing]))
          return start if shortest_facing_delta(start[:facing], desired_facing).abs < 0.05

          pivot = contact_pivot_point(start, defender)
          return start unless pivot

          short = shortest_facing_delta(start[:facing], desired_facing)
          long = short.positive? ? short - 360.0 : short + 360.0
          idle_allies = idle_ally_obstacles(start, defender, obstacles)
          short_blocked = align_direction_blocked_by_idle_ally?(start, pivot, short, defender, idle_allies)

          # Short wheel into an idle friend → take the other way as far as legally possible.
          if short_blocked
            other = sample_align_direction_furthest(
              start: start, pivot: pivot, delta: long, defender: defender, obstacles: obstacles
            )
            return other if align_moved?(start, other)

            fallback = sample_align_direction_furthest(
              start: start, pivot: pivot, delta: short, defender: defender, obstacles: obstacles
            )
            return fallback if align_moved?(start, fallback)

            return start
          end

          best = start
          best_score = align_pose_score(start, defender, desired_facing, obstacles, idle_allies: idle_allies)
          [ short, long ].each do |delta|
            next if delta.abs < 0.05

            path_best, path_score = sample_align_direction(
              start: start,
              pivot: pivot,
              delta: delta,
              defender: defender,
              desired_facing: desired_facing,
              obstacles: obstacles,
              idle_allies: idle_allies
            )
            next unless (path_score <=> best_score) == 1

            best = path_best
            best_score = path_score
          end
          best
        end

        def align_moved?(origin, pose)
          distance_between(origin, pose) > 0.05 ||
            shortest_facing_delta(origin[:facing], pose[:facing]).abs > 0.05
        end

        def sample_align_direction_furthest(start:, pivot:, delta:, defender:, obstacles:)
          return start if delta.abs < 0.05

          engage = CONFIG[:melee_contact_tolerance] + CONFIG[:contact_snap]
          best = start
          best_progress = 0.0
          steps = [ 8, (delta.abs / 10).ceil ].max
          steps = [ steps, 36 ].min
          steps.times do |index|
            progress = (index + 1).to_f / steps
            candidate = rotate_unit_around_point(start, pivot, delta * progress)
            candidate = separate_aligned_pose(candidate, defender) if rectangles_overlap?(candidate, defender)
            next if rectangles_overlap?(candidate, defender)
            next if distance_between_units(candidate, defender) > engage
            next if obstacles.any? { |obs|
              next false if obs[:entity_id] == candidate[:entity_id] || obs[:entity_id] == defender[:entity_id]
              next false if obs[:current_health].to_i <= 0

              rectangles_overlap?(candidate, obs) || distance_between_units(candidate, obs) < CONFIG[:melee_contact_tolerance]
            }
            next unless progress > best_progress

            best = candidate
            best_progress = progress
          end
          best
        end

        def sample_align_direction(start:, pivot:, delta:, defender:, desired_facing:, obstacles:, idle_allies:)
          engage = CONFIG[:melee_contact_tolerance] + CONFIG[:contact_snap]
          best = start
          best_score = align_pose_score(start, defender, desired_facing, obstacles, idle_allies: idle_allies)
          steps = [ 8, (delta.abs / 10).ceil ].max
          steps = [ steps, 36 ].min
          steps.times do |index|
            progress = (index + 1).to_f / steps
            candidate = rotate_unit_around_point(start, pivot, delta * progress)
            candidate = separate_aligned_pose(candidate, defender) if rectangles_overlap?(candidate, defender)
            next if rectangles_overlap?(candidate, defender)
            next if distance_between_units(candidate, defender) > engage
            next if obstacles.any? { |obs|
              next false if obs[:entity_id] == candidate[:entity_id] || obs[:entity_id] == defender[:entity_id]
              next false if obs[:current_health].to_i <= 0

              rectangles_overlap?(candidate, obs) || distance_between_units(candidate, obs) < CONFIG[:melee_contact_tolerance]
            }

            score = align_pose_score(candidate, defender, desired_facing, obstacles, idle_allies: idle_allies)
            next unless (score <=> best_score) == 1

            best = candidate
            best_score = score
          end
          [ best, best_score ]
        end

        def separate_aligned_pose(pose, defender)
          forward = facing_vector(pose[:facing])
          separated = pose
          12.times do
            break unless rectangles_overlap?(separated, defender)

            separated = clamp_battlefield_position(
              x: separated[:x] - (forward[:x] * 0.08),
              y: separated[:y] - (forward[:y] * 0.08),
              facing: separated[:facing]
            ).merge(pose.except(:x, :y, :facing))
          end
          separated
        end

        def align_pose_score(pose, defender, desired_facing, obstacles, idle_allies: nil)
          idle_allies ||= idle_ally_obstacles(pose, defender, obstacles)
          span = front_contact_span(pose, defender)
          facing_err = shortest_facing_delta(pose[:facing], desired_facing).abs
          free_side = align_side_blocked_by_idle_allies?(pose, defender, idle_allies) ? 0 : 1
          # Prefer the free half around idle friends, then face flush, then more models in contact.
          [ free_side, -facing_err, span ]
        end

        def align_side_blocked_by_idle_allies?(pose, defender, idle_allies)
          return false if idle_allies.nil? || idle_allies.empty?

          local = point_in_local_unit_space(pose, defender)
          idle_allies.any? do |ally|
            obs_local = point_in_local_unit_space(ally, defender)
            (local[:lateral] >= 0) == (obs_local[:lateral] >= 0)
          end
        end
      end
    end
  end
end
