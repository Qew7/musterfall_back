module Sim
  module Battle
    module Pathing
      # Collision world for one planning call: living trays + impassable terrain,
      # compiled once into SAT kernels. Queries (blocker, swept translation, wrap
      # vertices) all read this set — not a parallel obstacles/kernels pair.
      class Obstacles
        include Enumerable

        Kernel = Pathing::ObstacleKernel
        PAD = Pathing::CONTACT + 0.35

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
          @entries = Array(entries).select { |entry| usable?(entry) }
          @kernels = @entries.map { |entry| compile(entry) }
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
          self.class.new(@entries.reject { |entry| skip.include?(entry[:entity_id]) })
        end

        def +(other)
          self.class.new(@entries + Array(other))
        end

        def first_blocker(pose, contact_id: nil)
          px = pose[:x].to_f
          py = pose[:y].to_f
          phw, phd = Geometry::Obb.half_sizes(pose)
          pc, ps = Geometry::Obb.trig(pose[:facing])
          pr = Math.hypot(phw, phd) + Pathing::CONTACT
          pid = pose[:entity_id]

          @kernels.each do |kernel|
            next if kernel.id == pid

            dx = px - kernel.x
            dy = py - kernel.y
            reach = pr + kernel.radius
            next if ((dx * dx) + (dy * dy)) > (reach * reach)

            if contact_id && kernel.id == contact_id
              if Geometry::Obb.overlap?(px, py, phw, phd, pc, ps, kernel.x, kernel.y, kernel.hw, kernel.hd, kernel.c, kernel.s)
                return kernel.source
              end
            elsif Geometry::Obb.distance(px, py, phw, phd, pc, ps, kernel.x, kernel.y, kernel.hw, kernel.hd, kernel.c, kernel.s) < Pathing::CONTACT
              return kernel.source
            end
          end
          nil
        end

        def clear?(pose, contact_id: nil)
          first_blocker(pose, contact_id: contact_id).nil?
        end

        def translation_clear?(mover, from, to, contact_id: nil)
          length = Geometry::Battlefield.distance_between(from, to)
          phw, phd = Geometry::Obb.half_sizes(mover)
          pc, ps = Geometry::Obb.trig(to[:facing])
          mx = (from[:x].to_f + to[:x].to_f) * 0.5
          my = (from[:y].to_f + to[:y].to_f) * 0.5
          swept_hd = phd + (length * 0.5)
          pid = mover[:entity_id]
          pr = Math.hypot(phw, swept_hd) + Pathing::CONTACT

          @kernels.each do |kernel|
            next if kernel.id == pid

            dx = mx - kernel.x
            dy = my - kernel.y
            reach = pr + kernel.radius
            next if ((dx * dx) + (dy * dy)) > (reach * reach)

            if contact_id && kernel.id == contact_id
              return false if Geometry::Obb.overlap?(mx, my, phw, swept_hd, pc, ps, kernel.x, kernel.y, kernel.hw, kernel.hd, kernel.c, kernel.s)
            elsif Geometry::Obb.distance(mx, my, phw, swept_hd, pc, ps, kernel.x, kernel.y, kernel.hw, kernel.hd, kernel.c, kernel.s) < Pathing::CONTACT
              return false
            end
          end
          true
        end

        def segment_clear?(mover, from, to, contact_id: nil)
          return true if same_point?(from, to)

          heading = Geometry::Battlefield.heading_to(from, to)
          start = mover.merge(x: from[:x], y: from[:y], facing: heading)
          dest = mover.merge(x: to[:x], y: to[:y], facing: heading)
          return false if first_blocker(dest, contact_id: contact_id)

          translation_clear?(mover, start, dest, contact_id: contact_id)
        end

        # First hop from the live pose: wheel+translate, or turn+translate when the
        # heading is a 90° wrap the current frontage cannot wheel.
        def followable?(mover, to, contact_id: nil)
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

          steps = [ [ 8, (delta.abs / 10).ceil ].max, 20 ].min
          steps.times do |index|
            pose = Geometry::Battlefield.wheel_pose(mover, delta * ((index + 1).to_f / steps))
            sample = mover.merge(x: pose[:x], y: pose[:y], facing: pose[:facing])
            return false if first_blocker(sample, contact_id: contact_id)
          end
          true
        end

        def first_hit(mover, from, to, contact_id: nil)
          return nil if same_point?(from, to)

          heading = Geometry::Battlefield.heading_to(from, to)
          dist = Geometry::Battlefield.distance_between(from, to)
          steps = [ [ 8, (dist / 0.25).ceil ].max, 32 ].min
          steps.times do |index|
            t = (index + 1).to_f / steps
            pose = mover.merge(
              x: from[:x] + ((to[:x] - from[:x]) * t),
              y: from[:y] + ((to[:y] - from[:y]) * t),
              facing: heading
            )
            hit = first_blocker(pose, contact_id: contact_id)
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

        def wrap_vertices(mover, contact_id: nil)
          seen = {}
          @kernels.filter_map do |kernel|
            next if kernel.id == mover[:entity_id]
            next if contact_id && kernel.id == contact_id

            minkowski_points(mover, kernel).filter_map do |vertex|
              pose = fit_tray_on_board(mover.merge(x: vertex[:x], y: vertex[:y]))
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

        def usable?(entry)
          entry && !entry[:x].nil? && !entry[:y].nil? && entry[:current_health].to_i > 0
        end

        def compile(entry)
          x, y, hw, hd, c, s, radius = Geometry::Obb.kernel(entry)
          Kernel.new(entry[:entity_id], x, y, hw, hd, c, s, radius, entry)
        end

        def minkowski_points(mover, kernel)
          mhw, mhd = Geometry::Obb.half_sizes(mover)
          half = [ mhw, mhd ].max
          radius = Math.hypot(mhw, mhd)
          points = [ half + PAD, (2 * half) + PAD ].flat_map { |clearance| ring_points(kernel, clearance, :both) }
          # ponytail: hypot corners so a wide tray's diagonal clears; face mids stay at max(half).
          points.concat(ring_points(kernel, radius + PAD, :corners)) if radius > half + 0.05 &&
            kernel.source[:obstacle_kind] == :terrain
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
          return false unless tray_on_board?(turned)
          return false if first_blocker(turned, contact_id: contact_id)
          return true if same_point?(turned, to)

          dest = turned.merge(x: to[:x], y: to[:y])
          return false unless tray_on_board?(dest)
          return false if first_blocker(dest, contact_id: contact_id)

          translation_clear?(turned, turned, dest, contact_id: contact_id)
        end

        def tray_on_board?(pose)
          width = Geometry::Battlefield::CONFIG[:width]
          height = Geometry::Battlefield::CONFIG[:height]
          Geometry::Battlefield.unit_corners(pose).all? do |corner|
            corner[:x].between?(0.0, width) && corner[:y].between?(0.0, height)
          end
        end

        # ponytail: clamp instead of drop — off-board Minkowski corners left a 4x4
        # dead-ended on a house west face; if the clamp still overlaps, clear? drops it.
        def fit_tray_on_board(pose)
          width = Geometry::Battlefield::CONFIG[:width]
          height = Geometry::Battlefield::CONFIG[:height]
          corners = Geometry::Battlefield.unit_corners(pose)
          xs = corners.map { |corner| corner[:x] }
          ys = corners.map { |corner| corner[:y] }
          dx = 0.0
          dy = 0.0
          dx = -xs.min if xs.min < 0.0
          dy = -ys.min if ys.min < 0.0
          dx = width - xs.max if xs.max + dx > width
          dy = height - ys.max if ys.max + dy > height
          fitted = pose.merge(x: pose[:x] + dx, y: pose[:y] + dy)
          tray_on_board?(fitted) ? fitted : nil
        end

        def point(entry)
          { x: entry[:x].to_f, y: entry[:y].to_f }
        end

        def same_point?(left, right)
          Geometry::Battlefield.distance_between(left, right) <= 0.05
        end
      end
    end
  end
end
