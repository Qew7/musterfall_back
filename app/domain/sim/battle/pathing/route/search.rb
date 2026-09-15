module Sim
  module Battle
    module Pathing
      module Route
        # One immutable collision world per search. Node indices key visibility
        # and tie-breaking; no coordinate-array keys or retained adjacency lists.
        class Search
          def initialize(mover, start, finish, world, contact_id)
            @mover, @start, @finish, @world, @contact_id = mover, start, finish, world, contact_id
          end

          def call
            return [ @start, @finish ] if @world.first_segment_clear?(@mover, @finish, contact_id: @contact_id)

            @nodes = [ @start ]
            @world.route_points(@mover, contact_id: @contact_id).each do |vertex|
              @nodes << vertex unless Route.same?(vertex, @start) || Route.same?(vertex, @finish)
            end
            @nodes << @finish
            @indices = @nodes.each_with_index.to_h { |node, index| [ node.object_id, index ] }
            @visibility = {}
            @first_hops = {}
            @headings = @nodes.map { |node| Geometry::Battlefield.heading_to(@start, node) }
            @turn_cost = Geometry::Battlefield.turn_cost(@mover)
            @dist = Array.new(@nodes.length, Float::INFINITY)
            @prev = Array.new(@nodes.length)
            settled = Array.new(@nodes.length, false)
            @dist[0] = 0.0

            @nodes.length.times do
              u = nil
              best = Float::INFINITY
              @dist.each_index do |index|
                next if settled[index] || @dist[index] >= best

                best, u = @dist[index], index
              end
              break unless u

              settled[u] = true
              break if u == @nodes.length - 1

              u.zero? ? expand_start : expand(u, settled)
            end

            target = @nodes.length - 1
            if @dist[target].infinite?
              target = @nodes.each_index.reject { |i| @dist[i].infinite? }
                .min_by { |i| Geometry::Battlefield.distance_between(@nodes[i], @finish) }
            end
            reconstruct(target || 0)
          end

          def first_hop_open?(vertex, finish)
            # A partial route is tautened towards its reachable endpoint, not the
            # original goal; the receding-turn predicate depends on that endpoint.
            return Route.first_hop_open?(@world, @mover, vertex, finish, @contact_id) unless finish.equal?(@finish)

            @first_hops.fetch(vertex.object_id) do
              @first_hops[vertex.object_id] = Route.first_hop_open?(@world, @mover, vertex, finish, @contact_id)
            end
          end

          def segment_open?(from, to)
            key = edge_key(@indices.fetch(from.object_id), @indices.fetch(to.object_id))
            @visibility.fetch(key) do
              @visibility[key] = @world.segment_clear?(@mover, from, to, contact_id: @contact_id)
            end
          end

          private

          def expand_start
            opened = false
            (1...@nodes.length).each do |v|
              next unless first_hop_open?(@nodes[v], @finish)

              relax_first(v)
              opened = true
            end
            return if opened

            # Keep the existing geometric fallback when no wheel/turn first hop
            # is feasible. ManeuverSequence still validates the actual movement.
            (1...(@nodes.length - 1)).each do |v|
              relax_first(v) if segment_open?(@start, @nodes[v])
            end
          end

          def relax_first(v)
            @dist[v] = Geometry::Battlefield.distance_between(@start, @nodes[v]) +
              Route.first_hop_cost(@mover, @start, @nodes[v], @world, @contact_id)
            @prev[v] = 0
          end

          def expand(u, settled)
            candidates = []
            costs = []
            @nodes.each_index do |v|
              next if settled[v]

              distance = Geometry::Battlefield.distance_between(@nodes[u], @nodes[v])
              next if @dist[u] + distance >= @dist[v]

              # Preserve the existing symmetric, node-order turn penalty. Route
              # is a geometric guide, not a search over heading/formation states.
              i = u < v ? u : v
              j = u < v ? v : u
              outgoing = Geometry::Battlefield.heading_to(@nodes[i], @nodes[j])
              delta = Geometry::Battlefield.shortest_facing_delta(@headings[i], outgoing)
              cost = @dist[u] + (distance + (Geometry::Battlefield.turn_delta?(delta) ? @turn_cost : 0.0))
              next if cost >= @dist[v]

              candidates << v
              costs << cost
            end
            return if candidates.empty?

            mask = @world.segments_open_mask(@mover, @nodes[u], candidates.map { |v| @nodes[v] }, @contact_id)
            candidates.each_with_index do |v, index|
              open = mask.getbyte(index) == 1
              @visibility[edge_key(u, v)] = open
              next unless open

              @dist[v], @prev[v] = costs[index], u
            end
          end

          def edge_key(u, v)
            u < v ? u * @nodes.length + v : v * @nodes.length + u
          end

          def reconstruct(target)
            path = []
            while target
              path << @nodes[target]
              target = @prev[target]
            end
            path.reverse
          end
        end
      end
    end
  end
end
