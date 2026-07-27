module Sim
  module Geometry
    module Battlefield
      module Wheel
        # WHFB wheel: pivot on one front corner; MV cost = arc travelled by the outer front corner
        # (radius = footprint width). Remaining MV may be used to march after the wheel.
        def wheel_cost(unit, from_facing, to_facing)
          delta = shortest_facing_delta(from_facing, to_facing).abs
          return 0.0 if delta < 0.0001

          width = wheel_frontage(unit)
          return 0.0 if width <= 0

          (delta * Math::PI / 180.0) * width
        end

        def wheel_frontage(unit)
          unit_dimensions(unit)[:half_width] * 2.0
        end

        # Front-right for positive (right) wheel, front-left for negative (left) wheel.
        def wheel_pivot(unit, delta)
          corners = unit_corners(unit)
          delta.negative? ? corners[0] : corners[1]
        end

        # Outer front corner opposite the pivot — the model whose path sets the wheel distance.
        def wheel_outer_corner(unit, delta)
          corners = unit_corners(unit)
          delta.negative? ? corners[1] : corners[0]
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

          width = wheel_frontage(unit)
          return idle.merge(completed: false) if width <= 0

          full_cost = wheel_cost(unit, from_facing, desired)
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
          cost = wheel_cost(unit, from_facing, pose[:facing])
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
      end
    end
  end
end
