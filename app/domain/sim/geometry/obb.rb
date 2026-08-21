module Sim
  module Geometry
    # Allocation-free 2D OBB kernel (SAT overlap + clamp distance).
    # Optional C implementation in ext/sim_obb loads as Obb::Native.
    module Obb
      EPS = 1.0e-12

      module_function

      def native?
        const_defined?(:Native, false)
      end

      def trig(facing)
        radians = (((facing.to_f % 360.0) + 360.0) % 360.0) * (Math::PI / 180.0)
        [ Math.cos(radians), Math.sin(radians) ]
      end

      def half_sizes(unit)
        hw = (unit[:base_width] || unit[:width] || 0).to_f * 0.5
        hd = (unit[:base_depth] || unit[:depth] || 0).to_f * 0.5
        hw = 0.0 if hw.negative?
        hd = 0.0 if hd.negative?
        [ hw, hd ]
      end

      # Packed kernel: [x, y, hw, hd, cos, sin, circumradius]
      def kernel(unit)
        hw, hd = half_sizes(unit)
        c, s = trig(unit[:facing])
        [ unit[:x].to_f, unit[:y].to_f, hw, hd, c, s, Math.hypot(hw, hd) ]
      end

      def overlap_units?(left, right)
        overlap_kernels?(kernel(left), kernel(right))
      end

      def distance_units(left, right)
        distance_kernels(kernel(left), kernel(right))
      end

      def overlap_kernels?(left, right)
        overlap?(left[0], left[1], left[2], left[3], left[4], left[5], right[0], right[1], right[2], right[3], right[4], right[5])
      end

      def distance_kernels(left, right)
        distance(left[0], left[1], left[2], left[3], left[4], left[5], right[0], right[1], right[2], right[3], right[4], right[5])
      end

      def overlap?(ax, ay, ahw, ahd, ac, as_, bx, by, bhw, bhd, bc, bs)
        if native?
          return Native.overlap?(ax, ay, ahw, ahd, ac, as_, bx, by, bhw, bhd, bc, bs)
        end

        dx = bx - ax
        dy = by - ay
        return false if separated?(dx, dy, ac, as_, ac, as_, ahw, ahd, bc, bs, bhw, bhd)
        return false if separated?(dx, dy, -as_, ac, ac, as_, ahw, ahd, bc, bs, bhw, bhd)
        return false if separated?(dx, dy, bc, bs, ac, as_, ahw, ahd, bc, bs, bhw, bhd)
        return false if separated?(dx, dy, -bs, bc, ac, as_, ahw, ahd, bc, bs, bhw, bhd)

        true
      end

      def distance(ax, ay, ahw, ahd, ac, as_, bx, by, bhw, bhd, bc, bs)
        if native?
          return Native.distance(ax, ay, ahw, ahd, ac, as_, bx, by, bhw, bhd, bc, bs).round(2)
        end
        return 0.0 if overlap?(ax, ay, ahw, ahd, ac, as_, bx, by, bhw, bhd, bc, bs)

        min = Float::INFINITY
        4.times do |index|
          px, py = corner(ax, ay, ahw, ahd, ac, as_, index)
          d = point_distance(px, py, bx, by, bhw, bhd, bc, bs)
          min = d if d < min
        end
        4.times do |index|
          px, py = corner(bx, by, bhw, bhd, bc, bs, index)
          d = point_distance(px, py, ax, ay, ahw, ahd, ac, as_)
          min = d if d < min
        end
        min.round(2)
      end

      def closest_point(px, py, x, y, hw, hd, c, s)
        if native?
          return Native.closest_point(px, py, x, y, hw, hd, c, s)
        end

        lat, lng = local_xy(px, py, x, y, c, s)
        lat = lat.clamp(-hw, hw)
        lng = lng.clamp(-hd, hd)
        [
          x + ((-s) * lat) + (c * lng),
          y + (c * lat) + (s * lng)
        ]
      end

      def local_xy(px, py, x, y, c, s)
        dx = px - x
        dy = py - y
        [ ((-dx) * s) + (dy * c), (dx * c) + (dy * s) ]
      end

      def point_distance(px, py, x, y, hw, hd, c, s)
        lat, lng = local_xy(px, py, x, y, c, s)
        dlat = lat - lat.clamp(-hw, hw)
        dlng = lng - lng.clamp(-hd, hd)
        Math.hypot(dlat, dlng)
      end

      def corner(x, y, hw, hd, c, s, index)
        lng = index < 2 ? hd : -hd
        lat = (index == 0 || index == 3) ? -hw : hw
        [
          x + (c * lng) - (s * lat),
          y + (s * lng) + (c * lat)
        ]
      end

      def separated?(dx, dy, axis_x, axis_y, ac, as_, ahw, ahd, bc, bs, bhw, bhd)
        dist = ((dx * axis_x) + (dy * axis_y)).abs
        ra = radius(axis_x, axis_y, ac, as_, ahw, ahd)
        rb = radius(axis_x, axis_y, bc, bs, bhw, bhd)
        dist > ra + rb + EPS
      end

      def radius(axis_x, axis_y, c, s, hw, hd)
        ((axis_x * c) + (axis_y * s)).abs * hd + (((-axis_x) * s) + (axis_y * c)).abs * hw
      end
    end
  end
end

begin
  require File.expand_path("../../../../ext/sim_obb/sim_obb", __dir__)
rescue LoadError
end
