module Sim
  module Geometry
    module Battlefield
      module Targeting
        def line_of_sight_blockers(attacker, defender, blockers)
          line_start = front_center(attacker)
          line_end = closest_point_on_unit(line_start, defender)

          blockers.select do |blocker|
            next false if blocker[:entity_id] == attacker[:entity_id] || blocker[:entity_id] == defender[:entity_id]
            next false if blocker[:current_health].to_i <= 0

            line_intersects_unit?(line_start, line_end, blocker)
          end
        end

        def attack_victims(attacker, primary_target, enemies, attack_type)
          template = attack_type == "magic" ? attacker[:spell_template] : attacker[:shooting_template]
          living = enemies.select { |entry| entry[:current_health].to_i > 0 }

          case template
          when "volley"
            living
              .select { |entry| distance_between(entry, primary_target) <= CONFIG[:volley_radius] }
              .sort_by { |entry| distance_between(entry, primary_target) }
              .first(2)
              .each_with_index.map { |entry, index| { target: entry, multiplier: index.zero? ? 1 : 0.65 } }
          when "blast"
            living
              .select { |entry| distance_between(entry, primary_target) <= CONFIG[:blast_radius] }
              .map { |entry| { target: entry, multiplier: entry[:entity_id] == primary_target[:entity_id] ? 1 : 0.75 } }
          when "breath"
            living
              .select { |entry| in_front_arc?(attacker, entry, attacker[:facing], 70) }
              .select { |entry| distance_between(attacker, entry) <= distance_between(attacker, primary_target) + 1.5 }
              .map { |entry| { target: entry, multiplier: entry[:entity_id] == primary_target[:entity_id] ? 1 : 0.85 } }
          else
            [ { target: primary_target, multiplier: 1 } ]
          end
        end

        def line_intersects_unit?(start_point, end_point, unit)
          return true if point_inside_unit?(start_point, unit) || point_inside_unit?(end_point, unit)

          unit_edges(unit).any? { |edge_start, edge_end| segments_intersect?(start_point, end_point, edge_start, edge_end) }
        end

        def segments_intersect?(left_start, left_end, right_start, right_end)
          left_a = orientation(left_start, left_end, right_start)
          left_b = orientation(left_start, left_end, right_end)
          right_a = orientation(right_start, right_end, left_start)
          right_b = orientation(right_start, right_end, left_end)
          left_a != left_b && right_a != right_b
        end

        def orientation(start_point, middle, end_point)
          value = ((middle[:y] - start_point[:y]) * (end_point[:x] - middle[:x])) - ((middle[:x] - start_point[:x]) * (end_point[:y] - middle[:y]))
          return 0 if value.abs < 0.0001

          value.positive? ? 1 : 2
        end
      end
    end
  end
end
