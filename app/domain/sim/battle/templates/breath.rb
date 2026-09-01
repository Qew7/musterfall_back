module Sim
  module Battle
    module Templates
      class Breath < Base
        def polygon
          @polygon ||= Geometry::Battlefield.breath_teardrop_polygon(attacker, primary_target)
        end

        def template_descriptor(victims)
          shape = victims.dig(0, :polygon) || polygon
          {
            shape: "polygon",
            kind: "breath",
            length: Geometry::Battlefield::Templates::BREATH_LENGTH,
            points: shape,
            origin: Geometry::Battlefield.front_center(attacker),
            facing: Geometry::Battlefield.heading_to(
              Geometry::Battlefield.front_center(attacker),
              Geometry::Battlefield.closest_point_on_unit(Geometry::Battlefield.front_center(attacker), primary_target)
            ),
            affected_ids: victims.map { |entry| entry[:target][:entity_id] }
          }
        end

        def expected_damage(actor, target, vector, round_number, attack_type, enemies)
          damage_type = attack_type.to_s == "magic" ? "magic" : "shooting"
          attack_victims(enemies).sum do |entry|
            victim = entry[:target]
            per = Phases::AttackResolution.damage(actor, victim, damage_type, vector, round_number).to_f
            strike = strike_damage(victim, entry[:models_hit], per)
            models = [ victim[:models_remaining].to_i, 1 ].max
            strike * (1.0 + Math.log(models + 1, 10) * 0.15)
          end
        end

        def models_hit(unit)
          Geometry::Battlefield.models_hit_by_polygon(unit, polygon)
        end

        protected

        def build_victim_entry(entry, models_hit)
          super(entry, models_hit, multiplier: 1.0, auto_hit: true, polygon: polygon)
        end
      end
    end
  end
end
