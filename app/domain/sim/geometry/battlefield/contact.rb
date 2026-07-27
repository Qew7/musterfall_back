module Sim
  module Geometry
    module Battlefield
      module Contact
        def charge_destination(attacker, defender, facing = heading_to(attacker, defender))
          forward = facing_vector(facing)
          dims = unit_dimensions(attacker.merge(facing: facing))
          impact = closest_point_on_unit(attacker, defender)
          candidate = clamp_battlefield_position(
            x: impact[:x] - (forward[:x] * (dims[:half_depth] + CONFIG[:contact_padding])),
            y: impact[:y] - (forward[:y] * (dims[:half_depth] + CONFIG[:contact_padding])),
            facing: facing
          )
          # Back off along the approach if the OBB still clips the defender (angled contact).
          pose = attacker.merge(candidate)
          12.times do
            break unless rectangles_overlap?(pose, defender)

            pose = clamp_battlefield_position(
              x: pose[:x] - (forward[:x] * 0.15),
              y: pose[:y] - (forward[:y] * 0.15),
              facing: facing
            )
          end
          pose
        end

        def classify_attack_vector(attacker, defender)
          angle = angle_between(defender[:facing], defender, attacker)
          return "front" if angle <= 60
          return "rear" if angle >= 120

          "flank"
        end

        def facing_into_contact_face(attacker, defender)
          side = classify_attack_vector(attacker, defender)
          case side
          when "front"
            normalize_facing(defender[:facing] + 180)
          when "rear"
            normalize_facing(defender[:facing])
          else
            local = point_in_local_unit_space(attacker, defender)
            local[:lateral] >= 0 ? normalize_facing(defender[:facing] - 90) : normalize_facing(defender[:facing] + 90)
          end
        end
      end
    end
  end
end
