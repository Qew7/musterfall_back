module Sim
  module Geometry
    module Battlefield
      module Deployment
        def lane_anchors
          segment = CONFIG[:height] / 3
          {
            "left" => [ 1, segment / 2 ].max,
            "center" => CONFIG[:height] / 2,
            "right" => [ CONFIG[:height] - 2, (segment * 2) + (segment / 2) ].min
          }
        end

        def row_anchors
          {
            "reserve" => 0,
            "rear" => [ 1, (CONFIG[:deployment_depth] * 0.2).floor ].max,
            "support" => [ 2, (CONFIG[:deployment_depth] * 0.4).floor ].max,
            "front" => [ 3, CONFIG[:deployment_depth] - 2 ].max
          }
        end

        def default_deployment(row = "reserve", lane = "center")
          {
            x: row_anchors[row] || row_anchors["reserve"],
            y: lane_anchors[lane] || lane_anchors["center"],
            facing: 0.0
          }
        end

        def clamp_deployment_position(position)
          {
            x: position[:x].to_f.round.clamp(0, CONFIG[:deployment_depth] - 1),
            y: position[:y].to_f.round.clamp(0, CONFIG[:height] - 1),
            facing: normalize_facing(position[:facing].to_f)
          }
        end

        def sync_formation_slots_from_deployment(position)
          lane_boundary = CONFIG[:height] / 3.0
          lane = if position[:y] < lane_boundary
            Constants::LANE_ORDER[0]
          elsif position[:y] < lane_boundary * 2
            Constants::LANE_ORDER[1]
          else
            Constants::LANE_ORDER[2]
          end

          reserve_limit = [ 0, (CONFIG[:deployment_depth] * 0.15).floor - 1 ].max
          rear_limit = [ reserve_limit + 1, (CONFIG[:deployment_depth] * 0.3).floor - 1 ].max
          support_limit = [ rear_limit + 1, (CONFIG[:deployment_depth] * 0.5).floor - 1 ].max

          row = if position[:x] <= reserve_limit
            Constants::ROW_ORDER[3]
          elsif position[:x] <= rear_limit
            Constants::ROW_ORDER[2]
          elsif position[:x] <= support_limit
            Constants::ROW_ORDER[1]
          else
            Constants::ROW_ORDER[0]
          end

          { lane: lane, row: row }
        end

        def mirror_deployment(position)
          {
            x: CONFIG[:width] - 1 - position[:x],
            y: CONFIG[:height] - 1 - position[:y],
            facing: normalize_facing(position[:facing] + 180)
          }
        end

        def battle_position(position, side_index)
          local = clamp_deployment_position(position)
          side_index.zero? ? local : mirror_deployment(local)
        end
      end
    end
  end
end
