module Sim
  module Battle
    module Rules
      module Volley
        module Shooting
          module_function

          def applies?(attacker, attack_type)
            kind = attack_type.to_s == "magic" ? attacker[:spell_template] : attacker[:shooting_template]
            kind.to_s == "volley"
          end

          def attack_victims(attacker, primary_target, enemies)
            living = enemies.select { |entry| entry[:current_health].to_i > 0 }
            living
              .select { |entry| Geometry::Battlefield.distance_between(entry, primary_target) <= Geometry::Battlefield::CONFIG[:volley_radius] }
              .sort_by { |entry| Geometry::Battlefield.distance_between(entry, primary_target) }
              .first(2)
              .each_with_index.map { |entry, index| { target: entry, multiplier: index.zero? ? 1 : 0.65 } }
          end

          def template_descriptor(_attacker, primary_target, victims)
            {
              shape: "circle",
              radius: Geometry::Battlefield::CONFIG[:volley_radius],
              center: { x: primary_target[:x], y: primary_target[:y] },
              kind: "volley",
              affected_ids: victims.map { |entry| entry[:target][:entity_id] }
            }
          end
        end
      end
    end
  end
end
