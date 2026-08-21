module Sim
  module Battle
    module Pathing
      # Shortest polyline of tray-clear segments through the Minkowski vertices
      # of convex obstacles. The tray, not a point, is the thing that must fit.
      module Thread
        module_function

        def pull(mover:, goal:, obstacles: nil, contact_id: nil, kernels: nil, world: nil)
          start = point(mover)
          finish = point(goal)
          space = Obstacles.coerce(world || obstacles, kernels)
          wrap = space.except(mover[:entity_id], goal[:entity_id], contact_id)
          return { points: [ start ], blocker: nil, complete: true, wrapped: [] } if same?(start, finish)

          path = visible_path(mover, start, finish, wrap, contact_id)
          hit = wrap.first_hit(mover, start, finish, contact_id: contact_id)
          reached = path && same?(path.last, finish)
          pack(mover, path, finish, wrap, contact_id, reached ? nil : hit, hit ? [ hit ] : [])
        end

        def anchor(origin:, goal_point:, goal_unit:, contact_id:, **)
          return goal_point if goal_point && goal_unit && !same?(point(goal_point), point(goal_unit))
          return Geometry::Battlefield.charge_destination(origin, goal_unit) if contact_id && goal_unit

          goal_point || goal_unit || origin
        end

        def pack(mover, raw, finish, world, contact_id, blocker, wrapped)
          points = taut(mover, raw, world, contact_id)
          {
            points: points,
            blocker: blocker,
            complete: blocker.nil? && same?(points.last, finish),
            wrapped: Array(wrapped)
          }
        end

        def taut(mover, points, kernels, contact_id)
          world = Obstacles.coerce(kernels)
          return points if points.length <= 2

          pulled = [ points.first ]
          index = 0
          finish_index = points.length - 1
          while index < points.length - 1
            jump = finish_index
            while jump > index + 1
              visible = if index.zero?
                world.followable?(mover, points[jump], contact_id: contact_id) &&
                  !receding_turn?(mover, points[jump], points.last, world, contact_id)
              else
                world.segment_clear?(mover, points[index], points[jump], contact_id: contact_id)
              end
              break if visible

              jump -= 1
            end
            pulled << points[jump]
            index = jump
          end
          pulled
        end

        def segment_clear?(mover, from, to, kernels, contact_id)
          Obstacles.coerce(nil, kernels).segment_clear?(mover, from, to, contact_id: contact_id)
        end

        def first_hit(mover, from, to, kernels, contact_id)
          Obstacles.coerce(nil, kernels).first_hit(mover, from, to, contact_id: contact_id)
        end

        def visible_path(mover, start, finish, world, contact_id)
          nodes = [ start ]
          world.wrap_vertices(mover, contact_id: contact_id).each do |vertex|
            nodes << vertex unless same?(vertex, start) || same?(vertex, finish)
          end
          nodes << finish

          return [ start, finish ] if world.followable?(mover, finish, contact_id: contact_id)

          edges = Array.new(nodes.length) { [] }
          finish_index = nodes.length - 1
          nodes.each_index do |i|
            ((i + 1)...nodes.length).each do |j|
              visible = if i.zero?
                world.followable?(mover, nodes[j], contact_id: contact_id) &&
                  !receding_turn?(mover, nodes[j], finish, world, contact_id)
              else
                world.segment_clear?(mover, nodes[i], nodes[j], contact_id: contact_id)
              end
              next unless visible

              weight = Geometry::Battlefield.distance_between(nodes[i], nodes[j])
              weight += if i.zero?
                first_hop_cost(mover, nodes[i], nodes[j], world, contact_id)
              else
                corner_turn_cost(mover, nodes[0], nodes[i], nodes[j])
              end
              edges[i] << [ j, weight ]
              edges[j] << [ i, weight ]
            end
          end

          if edges[0].empty?
            (1...finish_index).each do |index|
              next unless world.segment_clear?(mover, nodes[0], nodes[index], contact_id: contact_id)

              weight = Geometry::Battlefield.distance_between(nodes[0], nodes[index])
              weight += first_hop_cost(mover, nodes[0], nodes[index], world, contact_id)
              edges[0] << [ index, weight ]
              edges[index] << [ 0, weight ]
            end
          end

          dist, prev = distances(nodes, edges, 0)
          target = nodes.length - 1
          return reconstruct(nodes, prev, target) unless dist[target].infinite?

          nearest = nearest_index(nodes, dist, finish)
          return [ start ] if nearest.nil? || nearest.zero?

          reconstruct(nodes, prev, nearest)
        end

        def receding_turn?(mover, vertex, finish, world, contact_id)
          heading = Geometry::Battlefield.heading_to(mover, vertex)
          delta = Geometry::Battlefield.shortest_facing_delta(mover[:facing], heading)
          return false unless Geometry::Battlefield.turn_delta?(delta)

          progress = Geometry::Battlefield.distance_between(mover, finish) -
            Geometry::Battlefield.distance_between(vertex, finish)
          goal_heading = Geometry::Battlefield.heading_to(mover, finish)
          off_goal = Geometry::Battlefield.shortest_facing_delta(heading, goal_heading).abs >= 60.0
          return true if off_goal && progress < 0.35
          return false if world.wheel_clear?(mover, heading, contact_id: contact_id)

          progress < -0.35
        end

        def first_hop_cost(mover, from, to, world, contact_id)
          heading = Geometry::Battlefield.heading_to(from, to)
          delta = Geometry::Battlefield.shortest_facing_delta(mover[:facing], heading)
          if Geometry::Battlefield.turn_delta?(delta) &&
              !world.wheel_clear?(mover, heading, contact_id: contact_id)
            Geometry::Battlefield.turn_cost(mover)
          else
            Geometry::Battlefield.wheel_cost(mover, mover[:facing], heading)
          end
        end

        def corner_turn_cost(mover, start, from, to)
          incoming = Geometry::Battlefield.heading_to(start, from)
          outgoing = Geometry::Battlefield.heading_to(from, to)
          delta = Geometry::Battlefield.shortest_facing_delta(incoming, outgoing)
          return 0.0 unless Geometry::Battlefield.turn_delta?(delta)

          Geometry::Battlefield.turn_cost(mover)
        end

        def distances(nodes, edges, source)
          dist = Array.new(nodes.length, Float::INFINITY)
          prev = Array.new(nodes.length)
          dist[source] = 0.0
          visited = {}

          nodes.length.times do
            u = nil
            best = Float::INFINITY
            dist.each_with_index do |cost, index|
              next if visited[index] || cost >= best

              best = cost
              u = index
            end
            break if u.nil? || best.infinite?

            visited[u] = true
            edges[u].each do |index, weight|
              alt = dist[u] + weight
              next unless alt < dist[index]

              dist[index] = alt
              prev[index] = u
            end
          end
          [ dist, prev ]
        end

        def nearest_index(nodes, dist, finish)
          best = nil
          best_d = Float::INFINITY
          finish_index = nodes.length - 1
          nodes.each_index do |index|
            next if index == finish_index
            next if dist[index].infinite?

            d = Geometry::Battlefield.distance_between(nodes[index], finish)
            next unless d < best_d

            best_d = d
            best = index
          end
          best
        end

        def reconstruct(nodes, prev, target)
          path = []
          cursor = target
          while cursor
            path.unshift(nodes[cursor])
            cursor = prev[cursor]
          end
          path
        end

        def point(entry)
          { x: entry[:x].to_f, y: entry[:y].to_f }
        end

        def same?(left, right)
          Geometry::Battlefield.distance_between(left, right) <= 0.05
        end
      end
    end
  end
end
