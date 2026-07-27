module Sim
  module Geometry
    module Battlefield
      module Core
        def config
          CONFIG
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

        def facing_vector(facing)
          radians = normalize_facing(facing) * (Math::PI / 180)
          { x: Math.cos(radians), y: Math.sin(radians) }
        end

        def right_vector(facing)
          facing_vector(facing + 90)
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

        def clamp_battlefield_position(position)
          {
            x: position[:x].to_f.clamp(0, CONFIG[:width] - 1),
            y: position[:y].to_f.clamp(0, CONFIG[:height] - 1),
            facing: normalize_facing(position[:facing].to_f)
          }
        end
      end
    end
  end
end
