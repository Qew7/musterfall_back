module Sim
  module Geometry
    module Battlefield
      # Polygon/line templates and per-model hit tests (model center under template).
      module Templates
        BREATH_LENGTH = 8.0
        BREATH_TIP_HALF_WIDTH = 0.3
        BREATH_BASE_HALF_WIDTH = 1.25
        LINE_CENTER_TOLERANCE = 0.05

        def line_template_segment(attacker, primary_target)
          start_point = front_center(attacker)
          through_point = { x: primary_target[:x].to_f, y: primary_target[:y].to_f }
          if distance_between(start_point, through_point) < 1e-6
            through_point = closest_point_on_unit(start_point, primary_target)
          end

          dx = through_point[:x] - start_point[:x]
          dy = through_point[:y] - start_point[:y]
          len = Math.hypot(dx, dy)
          if len < 1e-9
            forward = facing_vector(attacker[:facing])
            return [ start_point, ray_exit_point(start_point, forward[:x], forward[:y]) ]
          end

          ux = dx / len
          uy = dy / len
          [ start_point, ray_exit_point(start_point, ux, uy) ]
        end

        def ray_exit_point(origin, ux, uy)
          w = CONFIG[:width].to_f
          h = CONFIG[:height].to_f
          candidates = []
          candidates << (w - origin[:x]) / ux if ux.abs > 1e-9
          candidates << (0 - origin[:x]) / ux if ux.abs > 1e-9
          candidates << (h - origin[:y]) / uy if uy.abs > 1e-9
          candidates << (0 - origin[:y]) / uy if uy.abs > 1e-9
          t = candidates.select { |value| value > 1e-6 }.min || w
          { x: origin[:x] + (ux * t), y: origin[:y] + (uy * t) }
        end

        def models_hit_by_line(unit, start_point, end_point)
          model_cells(unit).count { |cell| model_center_on_line?(cell, start_point, end_point) }
        end

        # Thin tip at attacker front; thick base 8" along heading toward the primary target.
        def breath_teardrop_polygon(attacker, primary_target)
          origin = front_center(attacker)
          heading = heading_to(origin, closest_point_on_unit(origin, primary_target))
          forward = facing_vector(heading)
          right = right_vector(heading)
          tip = origin
          base_center = {
            x: tip[:x] + (forward[:x] * BREATH_LENGTH),
            y: tip[:y] + (forward[:y] * BREATH_LENGTH)
          }
          tip_left = {
            x: tip[:x] - (right[:x] * BREATH_TIP_HALF_WIDTH),
            y: tip[:y] - (right[:y] * BREATH_TIP_HALF_WIDTH)
          }
          tip_right = {
            x: tip[:x] + (right[:x] * BREATH_TIP_HALF_WIDTH),
            y: tip[:y] + (right[:y] * BREATH_TIP_HALF_WIDTH)
          }
          base_left = {
            x: base_center[:x] - (right[:x] * BREATH_BASE_HALF_WIDTH),
            y: base_center[:y] - (right[:y] * BREATH_BASE_HALF_WIDTH)
          }
          base_right = {
            x: base_center[:x] + (right[:x] * BREATH_BASE_HALF_WIDTH),
            y: base_center[:y] + (right[:y] * BREATH_BASE_HALF_WIDTH)
          }
          [ tip_left, tip_right, base_right, base_left ]
        end

        # One OBB per remaining model in files×ranks (front rank toward unit facing).
        def model_cells(unit)
          models = [ unit[:models_remaining].to_i, unit[:current_health].to_i > 0 ? 1 : 0 ].max
          return [] if models <= 0

          mw = [ unit[:model_width].to_f, 0.5 ].max
          md = [ unit[:model_depth].to_f, 0.5 ].max
          files = [ unit[:files].to_i, 1 ].max
          ranks = [ unit[:ranks].to_i, 1 ].max
          files = [ files, models ].min
          ranks = (models.to_f / files).ceil

          dims = unit_dimensions(unit)
          forward = facing_vector(unit[:facing])
          right = right_vector(unit[:facing])
          cells = []
          index = 0
          ranks.times do |rank|
            files.times do |file|
              break if index >= models

              # Rank 0 = front; file 0 = left (−right).
              lat = -dims[:half_width] + (mw * (file + 0.5))
              lon = dims[:half_depth] - (md * (rank + 0.5))
              cx = unit[:x] + (right[:x] * lat) + (forward[:x] * lon)
              cy = unit[:y] + (right[:y] * lat) + (forward[:y] * lon)
              cells << {
                entity_id: "#{unit[:entity_id]}:m#{index}",
                x: cx,
                y: cy,
                facing: unit[:facing],
                base_width: mw,
                base_depth: md,
                model_index: index
              }
              index += 1
            end
          end
          cells
        end

        def models_hit_by_polygon(unit, polygon)
          model_cells(unit).count { |cell| point_in_polygon?({ x: cell[:x], y: cell[:y] }, polygon) }
        end

        def model_center_on_line?(cell, start_point, end_point, tolerance: LINE_CENTER_TOLERANCE)
          point_on_segment?({ x: cell[:x], y: cell[:y] }, start_point, end_point, tolerance: tolerance)
        end

        def point_on_segment?(point, start_point, end_point, tolerance: LINE_CENTER_TOLERANCE)
          dx = end_point[:x] - start_point[:x]
          dy = end_point[:y] - start_point[:y]
          len_sq = (dx * dx) + (dy * dy)
          return distance_between(point, start_point) <= tolerance if len_sq < 1e-9

          t = (((point[:x] - start_point[:x]) * dx) + ((point[:y] - start_point[:y]) * dy)) / len_sq
          return false if t < -0.001 || t > 1.001

          proj = {
            x: start_point[:x] + (t * dx),
            y: start_point[:y] + (t * dy)
          }
          distance_between(point, proj) <= tolerance
        end

        def point_in_polygon?(point, polygon)
          return false if polygon.nil? || polygon.length < 3

          inside = false
          j = polygon.length - 1
          polygon.each_with_index do |pi, i|
            pj = polygon[j]
            intersects = ((pi[:y] > point[:y]) != (pj[:y] > point[:y])) &&
              (point[:x] < (((pj[:x] - pi[:x]) * (point[:y] - pi[:y]) / ((pj[:y] - pi[:y]).nonzero? || 1e-9)) + pi[:x]))
            inside = !inside if intersects
            j = i
          end
          inside
        end
      end
    end
  end
end
