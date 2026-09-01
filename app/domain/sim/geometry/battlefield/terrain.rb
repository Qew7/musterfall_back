module Sim
  module Geometry
    module Battlefield
      module Terrain
        def feature_footprint(feature)
          {
            entity_id: feature[:id],
            name: feature[:type].to_s,
            x: feature[:x].to_f,
            y: feature[:y].to_f,
            facing: 0.0,
            base_width: feature[:width].to_f,
            base_depth: feature[:depth].to_f,
            current_health: 1,
            obstacle_kind: :terrain,
            terrain_type: feature[:type].to_s
          }
        end

        def feature_as_obstacle(feature)
          feature_footprint(feature)
        end

        def impassable_obstacles(features)
          Array(features).select { |entry| entry[:impassable] || entry["impassable"] }
            .map { |entry| feature_as_obstacle(entry.transform_keys(&:to_sym)) }
        end

        def los_blocking_features(features)
          Array(features).select { |entry| entry[:blocks_los] }
        end

        def unit_midpoint(unit)
          { x: unit[:x].to_f, y: unit[:y].to_f }
        end

        def unit_midpoint_in_feature?(unit, feature)
          point_inside_unit?(unit_midpoint(unit), feature_footprint(feature))
        end

        def feature_at_midpoint(unit, features, type: nil)
          Array(features).find do |feature|
            next false if type && feature[:type].to_s != type.to_s

            unit_midpoint_in_feature?(unit, feature)
          end
        end

        def forest_id_at(unit, features)
          feature = feature_at_midpoint(unit, features, type: "forest")
          feature && feature[:id]
        end

        def in_forest?(unit, features)
          !forest_id_at(unit, features).nil?
        end

        def in_difficult?(unit, features)
          !feature_at_midpoint(unit, features, type: "difficult").nil?
        end

        # Charge into a forest-hidden unit only if the attacker shares that forest piece.
        def can_charge_through_terrain?(attacker, defender, features)
          defender_forest = forest_id_at(defender, features)
          return true unless defender_forest

          forest_id_at(attacker, features) == defender_forest
        end

        def move_cost_multiplier_at(unit, features, flying: false)
          return 1.0 if flying
          return 2.0 if in_difficult?(unit, features)

          1.0
        end

        def line_intersects_feature?(start_point, end_point, feature)
          footprint = feature_footprint(feature)
          return true if point_inside_unit?(start_point, footprint) || point_inside_unit?(end_point, footprint)

          unit_edges(footprint).any? do |edge_start, edge_end|
            segments_intersect?(start_point, end_point, edge_start, edge_end)
          end
        end
      end
    end
  end
end
