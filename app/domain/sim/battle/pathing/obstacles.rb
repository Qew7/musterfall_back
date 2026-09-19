module Sim
  module Battle
    module Pathing
      # Collision world for one planning call: living trays + impassable terrain,
      # compiled once into SAT kernels. Queries (blocker, swept translation, wrap
      # vertices) all read this set — not a parallel obstacles/kernels pair.
      class Obstacles
        include Enumerable

        Kernel = Pathing::ObstacleKernel
        UNIT_WRAP_PAD = Pathing::CONTACT + Pathing::TERRAIN_WRAP_PAD
        BATTLEFIELD_EDGE = {
          entity_id: "battlefield-edge",
          name: "край поля",
          terrain_type: "edge",
          obstacle_kind: :terrain
        }.freeze
        BOARD_W = Geometry::Battlefield::CONFIG[:width].to_f
        BOARD_H = Geometry::Battlefield::CONFIG[:height].to_f

        def self.merge(units, terrain = [])
          new(Pathing.merge_obstacles(units, terrain))
        end

        def self.around(mover, units:, terrain: [])
          mover_id = mover && mover[:entity_id]
          others = Array(units).reject { |entry| entry[:entity_id] == mover_id }
          merge(others, terrain)
        end

        def self.coerce(obstacles = nil, kernels = nil)
          return obstacles if obstacles.is_a?(self)
          return kernels if kernels.is_a?(self)
          return from_kernels(kernels) if obstacles.nil? && kernels
          return from_kernels(obstacles) if kernel_list?(obstacles)

          new(Array(obstacles))
        end

        def self.from_kernels(kernels)
          new(Array(kernels).map { |kernel| kernel.respond_to?(:source) ? kernel.source : kernel })
        end

        def self.kernel_list?(entries)
          entries.is_a?(Array) && entries.any? && entries.first.respond_to?(:source)
        end

        def initialize(entries)
          remember_kernels(Array(entries).select { |entry| usable?(entry) }.map { |entry| compile(entry) })
        end

        # Build directly from already-compiled kernels — skips coerce/compile so
        # except/+ can filter or concat the existing @kernels without rebuilding
        # from source. @entries mirrors the kernels' sources to stay consistent
        # with each/size, which are the only other readers of @entries.
        def self.from_compiled(kernels)
          instance = allocate
          instance.send(:init_from_compiled, Array(kernels))
          instance
        end

        def each(&block)
          @entries.each(&block)
        end

        def kernels
          @kernels
        end

        def size
          @entries.size
        end

        def except(*ids)
          skip = ids.flatten.compact
          self.class.from_compiled(@kernels.reject { |kernel| skip.include?(kernel.id) })
        end

        def +(other)
          other_kernels = other.is_a?(self.class) ? other.kernels : self.class.new(Array(other)).kernels
          self.class.from_compiled(@kernels + other_kernels)
        end

        def first_blocker(pose, contact_id: nil, x: pose[:x], y: pose[:y], facing: pose[:facing])
          px = x.to_f
          py = y.to_f
          phw, phd = cached_half(pose)
          pc, ps = Geometry::Obb.trig(facing)
          if Geometry::Obb.native?
            return decode_hit(native_hit(px, py, phw, phd, pc, ps, pose[:entity_id], contact_id, board: true))
          end

          unless x == pose[:x] && y == pose[:y] && facing == pose[:facing]
            pose = pose.merge(x: px, y: py, facing: facing)
          end
          return BATTLEFIELD_EDGE unless Geometry::Battlefield.tray_on_battlefield?(pose)

          pid = pose[:entity_id]
          pr = Math.hypot(phw, phd) + Pathing::CONTACT
          @kernels.each do |kernel|
            next if kernel.id == pid

            dx = px - kernel.x
            dy = py - kernel.y
            reach = pr + kernel.radius
            next if ((dx * dx) + (dy * dy)) > (reach * reach)

            if blocks_pose?(px, py, phw, phd, pc, ps, kernel, contact_id: contact_id)
              return kernel.source
            end
          end
          nil
        end

        def clear?(pose, contact_id: nil)
          first_blocker(pose, contact_id: contact_id).nil?
        end

        def translation_clear?(mover, from, to, contact_id: nil)
          from_facing = (from[:facing] || mover[:facing]).to_f
          to_facing = (to[:facing] || mover[:facing]).to_f
          phw, phd = cached_half(mover)
          pid = mover[:entity_id]
          if Geometry::Obb.native?
            fc, fs = Geometry::Obb.trig(from_facing)
            tc, ts = Geometry::Obb.trig(to_facing)
            return false unless native_on_board?(from[:x].to_f, from[:y].to_f, phw, phd, fc, fs)
            return false unless native_on_board?(to[:x].to_f, to[:y].to_f, phw, phd, tc, ts)
          else
            start = mover.merge(x: from[:x], y: from[:y], facing: from_facing)
            finish = mover.merge(x: to[:x], y: to[:y], facing: to_facing)
            return false unless Geometry::Battlefield.tray_on_battlefield?(start)
            return false unless Geometry::Battlefield.tray_on_battlefield?(finish)
          end

          length = Geometry::Battlefield.distance_between(from, to)
          mx = (from[:x].to_f + to[:x].to_f) * 0.5
          my = (from[:y].to_f + to[:y].to_f) * 0.5
          swept_hd = phd + (length * 0.5)
          pc, ps = Geometry::Obb.trig(to_facing)
          if Geometry::Obb.native?
            return native_hit(mx, my, phw, swept_hd, pc, ps, pid, contact_id, board: false).nil?
          end

          pr = Math.hypot(phw, swept_hd) + Pathing::CONTACT
          @kernels.each do |kernel|
            next if kernel.id == pid

            dx = mx - kernel.x
            dy = my - kernel.y
            reach = pr + kernel.radius
            next if ((dx * dx) + (dy * dy)) > (reach * reach)

            if blocks_pose?(mx, my, phw, swept_hd, pc, ps, kernel, contact_id: contact_id)
              return false
            end
          end
          true
        end

        def segment_clear?(mover, from, to, contact_id: nil)
          return true if same_point?(from, to)

          if Geometry::Obb.native?
            phw, phd = cached_half(mover)
            skip = @index_by_id.fetch(mover[:entity_id], -1)
            contact = contact_id ? @index_by_id.fetch(contact_id, -1) : -1
            return Geometry::Obb::Native.segment_clear?(
              from[:x].to_f, from[:y].to_f, to[:x].to_f, to[:y].to_f, phw, phd,
              @packed, skip, contact, Pathing::CONTACT, BOARD_W, BOARD_H
            )
          end

          heading = Geometry::Battlefield.heading_to(from, to)
          return false if first_blocker(mover, contact_id: contact_id, x: to[:x], y: to[:y], facing: heading)

          start = { x: from[:x], y: from[:y], facing: heading }
          dest = { x: to[:x], y: to[:y], facing: heading }
          translation_clear?(mover, start, dest, contact_id: contact_id)
        end

        def segments_open_mask(mover, from, dests, contact_id)
          return "" if dests.empty?
          return dests.map { |dest| segment_clear?(mover, from, dest, contact_id: contact_id) ? "\x01" : "\x00" }.join unless Geometry::Obb.native?

          phw, phd = cached_half(mover)
          skip = @index_by_id.fetch(mover[:entity_id], -1)
          contact = contact_id ? @index_by_id.fetch(contact_id, -1) : -1
          coordinates = []
          dests.each { |dest| coordinates << dest[:x].to_f << dest[:y].to_f }
          packed = coordinates.pack("d*")
          Geometry::Obb::Native.segments_clear(
            from[:x].to_f, from[:y].to_f, phw, phd, @packed, skip, contact, Pathing::CONTACT,
            BOARD_W, BOARD_H, packed
          )
        end

        # First hop from the live pose: wheel+translate, or turn+translate when the
        # heading is a 90° wrap the current frontage cannot wheel.
        def first_segment_clear?(mover, to, contact_id: nil)
          return false if same_point?(mover, to)

          heading = Geometry::Battlefield.heading_to(mover, to)
          return true if wheeled_to?(mover, heading, to, contact_id)
          return true if !wheel_clear?(mover, heading, contact_id: contact_id) &&
            turned_to?(mover, heading, to, contact_id)

          false
        end

        # Full wheel to `heading` at this width: arc cost fits the budget and the
        # swinging tray stays clear. Width enters through wheel_cost (radius = frontage).
        def wheel_fits?(mover, heading, budget, contact_id: nil)
          delta = Geometry::Battlefield.shortest_facing_delta(mover[:facing], heading)
          return true if delta.abs <= 0.05
          return false if budget.to_f <= 0.05

          cost = Geometry::Battlefield.wheel_cost(mover, mover[:facing], heading)
          return false if cost > budget.to_f + 0.0001

          wheel_clear?(mover, heading, contact_id: contact_id)
        end

        def wheel_clear?(mover, heading, contact_id: nil)
          delta = Geometry::Battlefield.shortest_facing_delta(mover[:facing], heading)
          return true if delta.abs <= 0.05

          if Geometry::Obb.native?
            phw, phd = cached_half(mover)
            pc, ps = Geometry::Obb.trig(mover[:facing])
            skip = @index_by_id.fetch(mover[:entity_id], -1)
            contact = contact_id ? @index_by_id.fetch(contact_id, -1) : -1
            return Geometry::Obb::Native.wheel_clear?(
              mover[:x].to_f, mover[:y].to_f, phw, phd, pc, ps,
              mover[:facing].to_f, heading.to_f,
              @packed, skip, contact, Pathing::CONTACT, BOARD_W, BOARD_H
            )
          end

          steps = [ [ 8, (delta.abs / 10).ceil ].max, 20 ].min
          steps.times do |index|
            pose = Geometry::Battlefield.wheel_pose(mover, delta * ((index + 1).to_f / steps))
            return false if first_blocker(mover, contact_id: contact_id, x: pose[:x], y: pose[:y], facing: pose[:facing])
          end
          true
        end

        def first_hit(mover, from, to, contact_id: nil)
          return nil if same_point?(from, to)

          heading = Geometry::Battlefield.heading_to(from, to)
          dist = Geometry::Battlefield.distance_between(from, to)
          steps = [ [ 8, (dist / 0.25).ceil ].max, 32 ].min
          fx = from[:x].to_f
          fy = from[:y].to_f
          dx = to[:x].to_f - fx
          dy = to[:y].to_f - fy
          steps.times do |index|
            t = (index + 1).to_f / steps
            hit = first_blocker(
              mover,
              contact_id: contact_id,
              x: fx + (dx * t),
              y: fy + (dy * t),
              facing: heading
            )
            return hit if hit
          end
          nil
        end

        # Minkowski vertices of every convex obstacle, in free space, on the board.
        # Legal tray pose in contact with the target: charge dest if free, otherwise
        # the nearest sampled contact ring pose that this world can hold.
        def contact_pose(mover, target, contact_id: nil)
          wrap = except(mover[:entity_id], contact_id)
          dest = Geometry::Battlefield.charge_destination(mover, target)
          heading = Geometry::Battlefield.heading_to(mover, dest)
          pose = mover.merge(x: dest[:x], y: dest[:y], facing: heading)
          return dest if wrap.clear?(pose, contact_id: contact_id)

          radius = Geometry::Battlefield.distance_between(dest, target)
          radius = 2.0 if radius < 0.5
          samples = 16.times.map do |index|
            angle = index * (360.0 / 16.0)
            vec = Geometry::Battlefield.facing_vector(angle)
            point = {
              x: target[:x].to_f + (vec[:x] * radius),
              y: target[:y].to_f + (vec[:y] * radius)
            }
            face = Geometry::Battlefield.heading_to(point, target)
            next unless wrap.clear?(mover.merge(x: point[:x], y: point[:y], facing: face), contact_id: contact_id)

            point.merge(facing: face)
          end.compact
          samples.min_by { |point| Geometry::Battlefield.distance_between(dest, point) }
        end

        def route_points(mover, contact_id: nil)
          return native_route_points(mover, contact_id) if Geometry::Obb.native?

          seen = {}
          @kernels.filter_map do |kernel|
            next if kernel.id == mover[:entity_id]
            next if contact_id && kernel.id == contact_id

            minkowski_points(mover, kernel).filter_map do |vertex|
              pose = Geometry::Battlefield.fit_tray_on_battlefield(mover.merge(x: vertex[:x], y: vertex[:y]))
              next unless pose
              next unless clear?(pose, contact_id: contact_id)

              key = [ pose[:x].round(2), pose[:y].round(2) ]
              next if seen[key]

              seen[key] = true
              { x: pose[:x], y: pose[:y] }
            end
          end.flatten
        end

        private

        def init_from_compiled(kernels)
          remember_kernels(kernels)
        end

        def remember_kernels(kernels)
          @kernels = kernels
          @entries = kernels.map(&:source)
          if Geometry::Obb.native?
            @index_by_id = {}
            kernels.each_with_index { |kernel, index| @index_by_id[kernel.id] = index if kernel.id }
            @packed = pack_kernels(kernels)
          end
          @half = {}
        end

        def pack_kernels(kernels)
          kernels.flat_map do |kernel|
            pad = terrain_kernel?(kernel) ? Pathing::TERRAIN_WRAP_PAD : Pathing::CONTACT
            [ kernel.x, kernel.y, kernel.hw, kernel.hd, kernel.c, kernel.s, kernel.radius, pad ]
          end.pack("d*")
        end

        def native_hit(px, py, phw, phd, pc, ps, pid, contact_id, board:)
          skip = @index_by_id.fetch(pid, -1)
          contact = contact_id ? @index_by_id.fetch(contact_id, -1) : -1
          Geometry::Obb::Native.blocker_index(
            px, py, phw, phd, pc, ps, @packed, skip, contact, Pathing::CONTACT,
            board ? BOARD_W : -1.0, BOARD_H
          )
        end

        def native_on_board?(px, py, phw, phd, pc, ps)
          Geometry::Obb::Native.blocker_index(
            px, py, phw, phd, pc, ps, "".freeze, -1, -1, Pathing::CONTACT, BOARD_W, BOARD_H
          ) != -1
        end

        def native_route_points(mover, contact_id)
          phw, phd = cached_half(mover)
          pc, ps = Geometry::Obb.trig(mover[:facing])
          skip = @index_by_id.fetch(mover[:entity_id], -1)
          contact = contact_id ? @index_by_id.fetch(contact_id, -1) : -1
          seen = {}
          Geometry::Obb::Native.route_points(
            phw, phd, pc, ps, @packed, skip, contact,
            UNIT_WRAP_PAD, Pathing::TERRAIN_WRAP_PAD, BOARD_W, BOARD_H, Pathing::CONTACT
          ).unpack("d*").each_slice(2).filter_map do |x, y|
            key = [ x.round(2), y.round(2) ]
            next if seen[key]

            seen[key] = true
            { x: x, y: y }
          end
        end

        def cached_half(pose)
          w = pose[:base_width] || pose[:width]
          d = pose[:base_depth] || pose[:depth]
          slot = (@half[w] ||= {})
          slot[d] ||= Geometry::Obb.half_sizes(pose)
        end

        def decode_hit(hit)
          return BATTLEFIELD_EDGE if hit == -1
          return @kernels[hit].source if hit

          nil
        end

        def usable?(entry)
          entry && !entry[:x].nil? && !entry[:y].nil? && entry[:current_health].to_f > 0
        end

        def compile(entry)
          x, y, hw, hd, c, s, radius = Geometry::Obb.kernel(entry)
          Kernel.new(entry[:entity_id], x, y, hw, hd, c, s, radius, entry)
        end

        def minkowski_points(mover, kernel)
          mhw, mhd = Geometry::Obb.half_sizes(mover)
          half = [ mhw, mhd ].max
          radius = Math.hypot(mhw, mhd)
          pad = terrain_kernel?(kernel) ? Pathing::TERRAIN_WRAP_PAD : UNIT_WRAP_PAD
          points = [ half + pad, (2 * half) + pad ].flat_map { |clearance| ring_points(kernel, clearance, :both) }
          # ponytail: hypot corners so a wide tray's diagonal clears; face mids stay at max(half).
          points.concat(ring_points(kernel, radius + pad, :corners)) if radius > half + 0.05 &&
            terrain_kernel?(kernel)
          points
        end

        def ring_points(kernel, clearance, parts)
          ihw = kernel.hw + clearance
          ihd = kernel.hd + clearance
          corners = 4.times.map { |index| Geometry::Obb.corner(kernel.x, kernel.y, ihw, ihd, kernel.c, kernel.s, index) }
          mids = 4.times.map do |index|
            a = corners[index]
            b = corners[(index + 1) % 4]
            [ (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5 ]
          end
          body = []
          body.concat(corners) if parts != :mids
          body.concat(mids) if parts != :corners
          body.map { |x, y| { x: x, y: y } }
        end

        def wheeled_to?(mover, heading, to, contact_id)
          wheel = Geometry::Battlefield.apply_wheel(mover, heading, 360.0)
          wheeled = mover.merge(x: wheel[:x], y: wheel[:y], facing: wheel[:facing])
          return false if first_blocker(wheeled, contact_id: contact_id)
          return true if same_point?(wheeled, to)

          dest = mover.merge(x: to[:x], y: to[:y], facing: wheeled[:facing])
          return false if first_blocker(dest, contact_id: contact_id)

          translation_clear?(wheeled, wheeled, dest, contact_id: contact_id)
        end

        def turned_to?(mover, heading, to, contact_id)
          delta = Geometry::Battlefield.shortest_facing_delta(mover[:facing], heading)
          return false unless Geometry::Battlefield.turn_delta?(delta)

          turn = Geometry::Battlefield.apply_turn(mover, heading, 360.0)
          return false unless turn[:completed]

          turned = Geometry::Battlefield.merge_footprint(mover, turn)
          return false unless Geometry::Battlefield.tray_on_battlefield?(turned)
          return false if first_blocker(turned, contact_id: contact_id)
          return true if same_point?(turned, to)

          dest = turned.merge(x: to[:x], y: to[:y])
          return false unless Geometry::Battlefield.tray_on_battlefield?(dest)
          return false if first_blocker(dest, contact_id: contact_id)

          translation_clear?(turned, turned, dest, contact_id: contact_id)
        end

        def point(entry)
          { x: entry[:x].to_f, y: entry[:y].to_f }
        end

        def same_point?(left, right)
          Geometry::Battlefield.distance_between(left, right) <= 0.05
        end

        def terrain_kernel?(kernel)
          Pathing.terrain_obstacle?(kernel.source)
        end

        # Charge target: overlap. Impassable terrain: TERRAIN_WRAP_PAD gap. Units: CONTACT gap.
        def blocks_pose?(px, py, phw, phd, pc, ps, kernel, contact_id: nil)
          if contact_id && kernel.id == contact_id
            return Geometry::Obb.overlap?(px, py, phw, phd, pc, ps, kernel.x, kernel.y, kernel.hw, kernel.hd, kernel.c, kernel.s)
          end
          if terrain_kernel?(kernel)
            return Geometry::Obb.distance(px, py, phw, phd, pc, ps, kernel.x, kernel.y, kernel.hw, kernel.hd, kernel.c, kernel.s) < Pathing::TERRAIN_WRAP_PAD
          end

          Geometry::Obb.distance(px, py, phw, phd, pc, ps, kernel.x, kernel.y, kernel.hw, kernel.hd, kernel.c, kernel.s) < Pathing::CONTACT
        end
      end
    end
  end
end
