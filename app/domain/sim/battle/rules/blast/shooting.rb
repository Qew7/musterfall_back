module Sim
  module Battle
    module Rules
      module Blast
        module Shooting
          # rule: blast | shooting | Circular AoE shot: primary ×1, models in splash radius ×0.75; heavyBlast radius ×1.5.
          module_function

          def applies?(attacker, attack_type)
            kind = attack_type.to_s == "magic" ? attacker[:spell_template] : attacker[:shooting_template]
            kind.to_s == "blast"
          end

          def attack_victims(attacker, primary_target, enemies)
            living = enemies.select { |entry| entry[:current_health].to_i > 0 }
            living
              .select { |entry| Geometry::Battlefield.distance_between(entry, primary_target) <= blast_radius(attacker) }
              .map { |entry| { target: entry, multiplier: entry[:entity_id] == primary_target[:entity_id] ? 1 : 0.75 } }
          end

          def template_descriptor(attacker, primary_target, victims)
            {
              shape: "circle",
              radius: blast_radius(attacker),
              center: { x: primary_target[:x], y: primary_target[:y] },
              kind: "blast",
              affected_ids: victims.map { |entry| entry[:target][:entity_id] }
            }
          end

          def blast_radius(attacker)
            base = Geometry::Battlefield::CONFIG[:blast_radius]
            Array(attacker[:abilities]).include?("heavyBlast") ? base * 1.5 : base
          end
          private_class_method :blast_radius
        end
      end
    end
  end
end
