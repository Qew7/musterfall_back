module Sim
  module Battle
    module Templates
      class Line < Base
        def segment
          @segment ||= Geometry::Battlefield.line_template_segment(attacker, primary_target)
        end

        def template_descriptor(victims)
          start_point, end_point = if victims.any?
            [ victims.first[:start], victims.first[:end] ]
          else
            segment
          end
          {
            shape: "line",
            kind: "line",
            start: start_point,
            end: end_point,
            length: Geometry::Battlefield.distance_between(start_point, end_point),
            affected_ids: victims.map { |entry| entry[:target][:entity_id] }
          }
        end

        def models_hit(unit)
          start_point, end_point = segment
          count = Geometry::Battlefield.models_hit_by_line(unit, start_point, end_point)
          return count if count.positive?
          return 0 unless Geometry::Battlefield.line_intersects_unit?(start_point, end_point, unit)

          tolerance = [
            unit[:model_width].to_f,
            unit[:model_depth].to_f,
            0.5
          ].max / 2.0
          Geometry::Battlefield.models_hit_by_line(unit, start_point, end_point, tolerance: tolerance)
        end

        protected

        def build_victim_entry(entry, models_hit)
          start_point, end_point = segment
          super(entry, models_hit, start: start_point, end: end_point)
        end
      end
    end
  end
end
