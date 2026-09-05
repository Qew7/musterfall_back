module Sim
  module Geometry
    module Battlefield
      module Contact
        def charge_destination(attacker, defender, facing = heading_to(attacker, defender))
          forward = facing_vector(facing)
          dims = unit_dimensions(attacker.merge(facing: facing))
          impact = closest_point_on_unit(attacker, defender)
          candidate = {
            x: impact[:x] - (forward[:x] * (dims[:half_depth] + CONFIG[:contact_padding])),
            y: impact[:y] - (forward[:y] * (dims[:half_depth] + CONFIG[:contact_padding])),
            facing: normalize_facing(facing)
          }
          # Back off along the approach if the OBB still clips the defender (angled contact).
          pose = attacker.merge(candidate)
          50.times do
            break unless rectangles_overlap?(pose, defender)

            pose = pose.merge(
              x: pose[:x] - (forward[:x] * 0.01),
              y: pose[:y] - (forward[:y] * 0.01),
              facing: facing
            )
          end
          pose
        end

        def side_contact?(attacker, defender)
          return false if rectangles_overlap?(attacker, defender)
          return false if distance_between_units(attacker, defender) > CONFIG[:contact_snap]
          return false if front_contact_span(attacker, defender) <= CONFIG[:contact_snap]

          desired = facing_into_contact_face(attacker, defender)
          shortest_facing_delta(attacker[:facing], desired).abs <= 5.0
        end

        def melee_contact?(left, right)
          side_contact?(left, right) || side_contact?(right, left)
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
