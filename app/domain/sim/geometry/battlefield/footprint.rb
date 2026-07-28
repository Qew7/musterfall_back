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
          dims = unit_dimensions(unit)
          forward = facing_vector(unit[:facing])
          right = right_vector(unit[:facing])
          hw = dims[:half_width]
          hd = dims[:half_depth]

          [
            { x: unit[:x] + (forward[:x] * hd) - (right[:x] * hw), y: unit[:y] + (forward[:y] * hd) - (right[:y] * hw) },
            { x: unit[:x] + (forward[:x] * hd) + (right[:x] * hw), y: unit[:y] + (forward[:y] * hd) + (right[:y] * hw) },
            { x: unit[:x] - (forward[:x] * hd) + (right[:x] * hw), y: unit[:y] - (forward[:y] * hd) + (right[:y] * hw) },
            { x: unit[:x] - (forward[:x] * hd) - (right[:x] * hw), y: unit[:y] - (forward[:y] * hd) - (right[:y] * hw) }
          ]
        end

        def front_center(unit)
          half_depth = unit_dimensions(unit)[:half_depth]
          forward = facing_vector(unit[:facing])
          { x: unit[:x] + (forward[:x] * half_depth), y: unit[:y] + (forward[:y] * half_depth) }
        end

        def point_in_local_unit_space(point, unit)
          forward = facing_vector(unit[:facing])
          right = right_vector(unit[:facing])
          dx = point[:x] - unit[:x]
          dy = point[:y] - unit[:y]
          {
            lateral: (dx * right[:x]) + (dy * right[:y]),
            longitudinal: (dx * forward[:x]) + (dy * forward[:y])
          }
        end

        def point_inside_unit?(point, unit)
          dims = unit_dimensions(unit)
          local = point_in_local_unit_space(point, unit)
          local[:lateral].abs <= dims[:half_width] && local[:longitudinal].abs <= dims[:half_depth]
        end

        def closest_point_on_unit(point, unit)
          dims = unit_dimensions(unit)
          forward = facing_vector(unit[:facing])
          right = right_vector(unit[:facing])
          local = point_in_local_unit_space(point, unit)
          clamped_lateral = local[:lateral].clamp(-dims[:half_width], dims[:half_width])
          clamped_longitudinal = local[:longitudinal].clamp(-dims[:half_depth], dims[:half_depth])
          {
            x: unit[:x] + (right[:x] * clamped_lateral) + (forward[:x] * clamped_longitudinal),
            y: unit[:y] + (right[:y] * clamped_lateral) + (forward[:y] * clamped_longitudinal)
          }
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

        def tray_clear_of_enemies?(unit, enemies, clearance:)
          nearest_enemy_within_tray_clearance(unit, enemies, clearance: clearance).nil?
        end

        def distance_between_units(left, right)
          return 0 if rectangles_overlap?(left, right)

          min_distance = Float::INFINITY
          unit_corners(left).each do |corner|
            unit_edges(right).each do |start_point, end_point|
              min_distance = [ min_distance, distance_point_to_segment(corner, start_point, end_point) ].min
            end
          end
          unit_corners(right).each do |corner|
            unit_edges(left).each do |start_point, end_point|
              min_distance = [ min_distance, distance_point_to_segment(corner, start_point, end_point) ].min
            end
          end
          min_distance
        end

        def rectangles_overlap?(left, right)
          axes = separating_axes(left) + separating_axes(right)
          axes.all? do |axis|
            left_projection = project_unit_onto_axis(left, axis)
            right_projection = project_unit_onto_axis(right, axis)
            left_projection[:max] >= right_projection[:min] && right_projection[:max] >= left_projection[:min]
          end
        end

        def separating_axes(unit)
          [ facing_vector(unit[:facing]), right_vector(unit[:facing]) ]
        end

        def project_unit_onto_axis(unit, axis)
          dots = unit_corners(unit).map { |point| (point[:x] * axis[:x]) + (point[:y] * axis[:y]) }
          { min: dots.min, max: dots.max }
        end
      end
    end
  end
end
