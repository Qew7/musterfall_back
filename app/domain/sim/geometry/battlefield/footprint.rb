module Sim
  module Geometry
    module Battlefield
      module Footprint
        def unit_dimensions(unit)
          {
            half_width: [ (unit[:base_width] || unit[:width] || 0) / 2.0, 0 ].max,
            half_depth: [ (unit[:base_depth] || unit[:depth] || 0) / 2.0, 0 ].max
          }
        end

        def unit_corners(unit)
          x, y, hw, hd, c, s = Sim::Geometry::Obb.kernel(unit)
          4.times.map do |index|
            cx, cy = Sim::Geometry::Obb.corner(x, y, hw, hd, c, s, index)
            { x: cx, y: cy }
          end
        end

        def front_center(unit)
          half_depth = unit_dimensions(unit)[:half_depth]
          forward = facing_vector(unit[:facing])
          { x: unit[:x] + (forward[:x] * half_depth), y: unit[:y] + (forward[:y] * half_depth) }
        end

        def point_in_local_unit_space(point, unit)
          c, s = Sim::Geometry::Obb.trig(unit[:facing])
          lat, lng = Sim::Geometry::Obb.local_xy(
            point[:x].to_f, point[:y].to_f, unit[:x].to_f, unit[:y].to_f, c, s
          )
          { lateral: lat, longitudinal: lng }
        end

        def point_inside_unit?(point, unit)
          dims = unit_dimensions(unit)
          local = point_in_local_unit_space(point, unit)
          local[:lateral].abs <= dims[:half_width] && local[:longitudinal].abs <= dims[:half_depth]
        end

        def closest_point_on_unit(point, unit)
          c, s = Sim::Geometry::Obb.trig(unit[:facing])
          hw, hd = Sim::Geometry::Obb.half_sizes(unit)
          x, y = Sim::Geometry::Obb.closest_point(
            point[:x].to_f, point[:y].to_f,
            unit[:x].to_f, unit[:y].to_f, hw, hd, c, s
          )
          { x: x, y: y }
        end

        def distance_point_to_segment(point, segment_start, segment_end)
          closest = closest_point_on_segment(point, segment_start, segment_end)
          distance_between(point, closest)
        end

        def closest_point_on_segment(point, segment_start, segment_end)
          dx = segment_end[:x] - segment_start[:x]
          dy = segment_end[:y] - segment_start[:y]
          length_squared = (dx * dx) + (dy * dy)
          return { x: segment_start[:x].to_f, y: segment_start[:y].to_f } if length_squared.zero?

          projection = (((point[:x] - segment_start[:x]) * dx) + ((point[:y] - segment_start[:y]) * dy)) / length_squared
          t = projection.clamp(0, 1)
          { x: segment_start[:x] + (dx * t), y: segment_start[:y] + (dy * t) }
        end

        def unit_edges(unit)
          corners = unit_corners(unit)
          corners.each_with_index.map { |corner, index| [ corner, corners[(index + 1) % corners.length] ] }
        end

        def nearest_enemy_within_tray_clearance(unit, enemies, clearance:)
          Array(enemies).each_with_object([]) do |enemy, matches|
            next if enemy[:current_health].to_i <= 0

            distance = distance_between_units(unit, enemy)
            matches << [ distance, enemy ] if distance <= clearance.to_f
          end.min_by(&:first)&.last
        end

        def distance_between_units(left, right)
          Sim::Geometry::Obb.distance_units(left, right)
        end

        def rectangles_overlap?(left, right)
          Sim::Geometry::Obb.overlap_units?(left, right)
        end

        def project_unit_onto_axis(unit, axis)
          dots = unit_corners(unit).map { |point| (point[:x] * axis[:x]) + (point[:y] * axis[:y]) }
          { min: dots.min, max: dots.max }
        end
      end
    end
  end
end
