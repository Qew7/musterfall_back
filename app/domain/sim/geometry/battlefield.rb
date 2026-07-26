module Sim
  module Geometry
    module Battlefield
      CONFIG = {
        width: 32,
        height: 24,
        deployment_depth: 10,
        front_arc_degrees: 120,
        wheel_step_degrees: 45,
        contact_padding: 0.35,
        melee_contact_tolerance: 0.4,
        blast_radius: 1.6,
        volley_radius: 1.4
      }.freeze

      module_function

      def config
        CONFIG
      end

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

      def normalize_facing(value)
        ((value % 360) + 360) % 360
      end

      def rotate_facing(facing, delta)
        normalize_facing(facing + delta)
      end

      def shortest_facing_delta(from_facing, to_facing)
        delta = normalize_facing(to_facing) - normalize_facing(from_facing)
        return delta - 360 if delta > 180
        return delta + 360 if delta < -180

        delta
      end

      # Wheel pivots on a front corner: outer edge travels an arc of radius = footprint width.
      def wheel_cost(unit, from_facing, to_facing)
        delta = shortest_facing_delta(from_facing, to_facing).abs
        return 0.0 if delta < 0.0001

        width = unit_dimensions(unit)[:half_width] * 2.0
        return 0.0 if width <= 0

        (delta * Math::PI / 180.0) * width
      end

      # Front-right for positive (right) wheel, front-left for negative (left) wheel.
      def wheel_pivot(unit, delta)
        corners = unit_corners(unit)
        delta.negative? ? corners[0] : corners[1]
      end

      # Rotate unit center around the chosen front corner by delta degrees.
      def wheel_pose(unit, delta)
        return unit.merge(facing: normalize_facing(unit[:facing])) if delta.abs < 0.0001

        pivot = wheel_pivot(unit, delta)
        radians = delta * (Math::PI / 180.0)
        cos_a = Math.cos(radians)
        sin_a = Math.sin(radians)
        vx = unit[:x] - pivot[:x]
        vy = unit[:y] - pivot[:y]
        clamp_battlefield_position(
          x: pivot[:x] + (vx * cos_a) - (vy * sin_a),
          y: pivot[:y] + (vx * sin_a) + (vy * cos_a),
          facing: normalize_facing(unit[:facing] + delta)
        )
      end

      # Spend MV on an arc wheel toward to_facing. Center moves with the formation.
      def apply_wheel(unit, to_facing, movement_budget)
        budget = [ movement_budget.to_f, 0.0 ].max
        from_facing = normalize_facing(unit[:facing])
        desired = normalize_facing(to_facing)
        delta = shortest_facing_delta(from_facing, desired)
        idle = {
          x: unit[:x].to_f,
          y: unit[:y].to_f,
          facing: from_facing,
          cost: 0.0,
          remaining: budget,
          completed: delta.abs < 0.0001,
          delta: 0.0
        }
        return idle if delta.abs < 0.0001

        width = unit_dimensions(unit)[:half_width] * 2.0
        return idle.merge(completed: false) if width <= 0

        full_cost = (delta.abs * Math::PI / 180.0) * width
        limited_delta = if full_cost <= budget
          delta
        elsif budget <= 0
          0.0
        else
          max_degrees = (budget / width) * (180.0 / Math::PI)
          delta.negative? ? -[ delta.abs, max_degrees ].min : [ delta.abs, max_degrees ].min
        end
        return idle if limited_delta.abs < 0.0001

        pose = wheel_pose(unit, limited_delta)
        cost = (limited_delta.abs * Math::PI / 180.0) * width
        {
          x: pose[:x],
          y: pose[:y],
          facing: pose[:facing],
          cost: cost,
          remaining: [ budget - cost, 0.0 ].max,
          completed: shortest_facing_delta(pose[:facing], desired).abs < 0.05,
          delta: limited_delta
        }
      end

      def facing_vector(facing)
        radians = normalize_facing(facing) * (Math::PI / 180)
        { x: Math.cos(radians), y: Math.sin(radians) }
      end

      def right_vector(facing)
        facing_vector(facing + 90)
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

      def clamp_battlefield_position(position)
        {
          x: position[:x].to_f.clamp(0, CONFIG[:width] - 1),
          y: position[:y].to_f.clamp(0, CONFIG[:height] - 1),
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

      def angle_between(facing, from, to)
        forward = facing_vector(facing)
        dx = to[:x] - from[:x]
        dy = to[:y] - from[:y]
        length = Math.hypot(dx, dy)
        length = 1 if length.zero?
        dot = ((forward[:x] * dx) + (forward[:y] * dy)) / length
        Math.acos(dot.clamp(-1, 1)) * (180 / Math::PI)
      end

      def in_front_arc?(origin, target, facing, arc = CONFIG[:front_arc_degrees])
        angle_between(facing, origin, target) <= (arc / 2.0)
      end

      def distance_between(left, right)
        Math.hypot(right[:x] - left[:x], right[:y] - left[:y])
      end

      def heading_to(origin, target)
        normalize_facing(Math.atan2(target[:y] - origin[:y], target[:x] - origin[:x]) * (180 / Math::PI))
      end

      def move_along_facing(position, distance)
        vector = facing_vector(position[:facing])
        position.merge(
          x: position[:x] + (vector[:x] * distance),
          y: position[:y] + (vector[:y] * distance)
        )
      end

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
        dx = segment_end[:x] - segment_start[:x]
        dy = segment_end[:y] - segment_start[:y]
        length_squared = (dx * dx) + (dy * dy)
        return distance_between(point, segment_start) if length_squared.zero?

        projection = (((point[:x] - segment_start[:x]) * dx) + ((point[:y] - segment_start[:y]) * dy)) / length_squared
        t = projection.clamp(0, 1)
        closest = { x: segment_start[:x] + (dx * t), y: segment_start[:y] + (dy * t) }
        distance_between(point, closest)
      end

      def unit_edges(unit)
        corners = unit_corners(unit)
        corners.each_with_index.map { |corner, index| [ corner, corners[(index + 1) % corners.length] ] }
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

      def charge_destination(attacker, defender, facing = heading_to(attacker, defender))
        forward = facing_vector(facing)
        dims = unit_dimensions(attacker.merge(facing: facing))
        impact = closest_point_on_unit(attacker, defender)
        clamp_battlefield_position(
          x: impact[:x] - (forward[:x] * (dims[:half_depth] + CONFIG[:contact_padding])),
          y: impact[:y] - (forward[:y] * (dims[:half_depth] + CONFIG[:contact_padding])),
          facing: facing
        )
      end

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

      def classify_attack_vector(attacker, defender)
        angle = angle_between(defender[:facing], defender, attacker)
        return "front" if angle <= 60
        return "rear" if angle >= 120

        "flank"
      end

      def separating_axes(unit)
        [ facing_vector(unit[:facing]), right_vector(unit[:facing]) ]
      end

      def project_unit_onto_axis(unit, axis)
        dots = unit_corners(unit).map { |point| (point[:x] * axis[:x]) + (point[:y] * axis[:y]) }
        { min: dots.min, max: dots.max }
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
