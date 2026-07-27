module Sim
  module Geometry
    module Battlefield
      # Polygon templates (breath teardrop) and per-model coverage.
      module Templates
        BREATH_LENGTH = 8.0
        BREATH_TIP_HALF_WIDTH = 0.3
        BREATH_BASE_HALF_WIDTH = 1.25
        COVERAGE_THRESHOLD = 0.5
        COVERAGE_SAMPLES = 5

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
          model_cells(unit).count { |cell| coverage_fraction(cell, polygon) > COVERAGE_THRESHOLD }
        end

        def coverage_fraction(model_unit, polygon)
          samples = sample_points_in_unit(model_unit, COVERAGE_SAMPLES)
          return 0.0 if samples.empty?

          inside = samples.count { |point| point_in_polygon?(point, polygon) }
          inside.to_f / samples.length
        end

        def sample_points_in_unit(unit, grid)
          dims = unit_dimensions(unit)
          forward = facing_vector(unit[:facing])
          right = right_vector(unit[:facing])
          points = []
          grid.times do |iy|
            grid.times do |ix|
              u = (ix + 0.5) / grid
              v = (iy + 0.5) / grid
              lat = -dims[:half_width] + (2 * dims[:half_width] * u)
              lon = -dims[:half_depth] + (2 * dims[:half_depth] * v)
              points << {
                x: unit[:x] + (right[:x] * lat) + (forward[:x] * lon),
                y: unit[:y] + (right[:y] * lat) + (forward[:y] * lon)
              }
            end
          end
          points
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
