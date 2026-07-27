module Sim
  module Battle
    module Rules
      module Blast
        module Shooting
          module_function

          def applies?(attacker, attack_type)
            kind = attack_type.to_s == "magic" ? attacker[:spell_template] : attacker[:shooting_template]
            kind.to_s == "blast"
          end

          def attack_victims(_attacker, primary_target, enemies)
            living = enemies.select { |entry| entry[:current_health].to_i > 0 }
            living
              .select { |entry| Geometry::Battlefield.distance_between(entry, primary_target) <= Geometry::Battlefield::CONFIG[:blast_radius] }
              .map { |entry| { target: entry, multiplier: entry[:entity_id] == primary_target[:entity_id] ? 1 : 0.75 } }
          end

          def template_descriptor(_attacker, primary_target, victims)
            {
              shape: "circle",
              radius: Geometry::Battlefield::CONFIG[:blast_radius],
              center: { x: primary_target[:x], y: primary_target[:y] },
              kind: "blast",
              affected_ids: victims.map { |entry| entry[:target][:entity_id] }
            }
          end
        end
      end
    end
  end
end
