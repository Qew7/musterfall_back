module Sim
  module Battle
    module Pathing
      # Shortest clear route through obstacle checkpoints.
      module Route
        module_function

        def pull(mover:, goal:, obstacles: nil, contact_id: nil, kernels: nil, world: nil)
          start = point(mover)
          finish = point(goal)
          space = Obstacles.coerce(world || obstacles, kernels)
          wrap = space.except(mover[:entity_id], goal[:entity_id], contact_id)
          return { points: [ start ], blocker: nil, complete: true } if same?(start, finish)

          search = Search.new(mover, start, finish, wrap, contact_id)
          path = search.call
          reached = path && same?(path.last, finish)
          hit = reached ? nil : wrap.first_hit(mover, start, finish, contact_id: contact_id)
          points = taut(mover, path, wrap, contact_id, search: search)
          { points: points, blocker: hit, complete: hit.nil? && same?(points.last, finish) }
        end

        def anchor(origin:, goal_point:, goal_unit:, contact_id:, **)
          return goal_point if goal_point && goal_unit && !same?(point(goal_point), point(goal_unit))
          return Geometry::Battlefield.charge_destination(origin, goal_unit) if contact_id && goal_unit

          goal_point || goal_unit || origin
        end

        def taut(mover, points, kernels, contact_id, search: nil)
          world = Obstacles.coerce(kernels)
          return points if points.length <= 2

          pulled = [ points.first ]
          index = 0
          finish_index = points.length - 1
          while index < points.length - 1
            jump = finish_index
            while jump > index + 1
              visible = if index.zero?
                if search
                  search.first_hop_open?(points[jump], points.last)
                else
                  first_hop_open?(world, mover, points[jump], points.last, contact_id)
                end
              else
                if search
                  search.segment_open?(points[index], points[jump])
                else
                  world.segment_clear?(mover, points[index], points[jump], contact_id: contact_id)
                end
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

        def first_hop_open?(world, mover, vertex, finish, contact_id)
          world.first_segment_clear?(mover, vertex, contact_id: contact_id) &&
            !receding_turn?(mover, vertex, finish, world, contact_id)
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

        def point(entry)
          point = { x: entry[:x].to_f, y: entry[:y].to_f }
          point[:facing] = entry[:facing].to_f if entry.key?(:facing)
          point
        end

        def same?(left, right)
          Geometry::Battlefield.distance_between(left, right) <= 0.05
        end
      end
    end
  end
end
