module Sim
  module Battle
    module Rules
      module Breath
        # Breath weapon overrides for the shooting (missile) phase.
        # Fixed 8" teardrop; models >50% covered are hit (auto-hit).
        module Shooting
          module_function

          def applies?(attacker, attack_type)
            kind = attack_type == "magic" ? attacker[:spell_template] : attacker[:shooting_template]
            kind.to_s == "breath"
          end

          def attack_victims(attacker, primary_target, enemies)
            living = enemies.select { |entry| entry[:current_health].to_i > 0 }
            polygon = Geometry::Battlefield.breath_teardrop_polygon(attacker, primary_target)
            living.filter_map do |entry|
              models_hit = Geometry::Battlefield.models_hit_by_polygon(entry, polygon)
              next if models_hit <= 0

              {
                target: entry,
                models_hit: models_hit,
                multiplier: 1.0,
                auto_hit: true,
                polygon: polygon
              }
            end
          end

          def template_descriptor(attacker, primary_target, victims)
            polygon = victims.dig(0, :polygon) || Geometry::Battlefield.breath_teardrop_polygon(attacker, primary_target)
            {
              shape: "polygon",
              kind: "breath",
              length: Geometry::Battlefield::Templates::BREATH_LENGTH,
              points: polygon,
              origin: Geometry::Battlefield.front_center(attacker),
              facing: Geometry::Battlefield.heading_to(
                Geometry::Battlefield.front_center(attacker),
                Geometry::Battlefield.closest_point_on_unit(Geometry::Battlefield.front_center(attacker), primary_target)
              ),
              affected_ids: victims.map { |entry| entry[:target][:entity_id] }
            }
          end

          def resolve_missile_strike!(phase:, actor:, host:, profile:, primary:, vector:, victims:, attack_type:, acting_side:, target_side:, round_number:, blockers:)
            victims.each do |victim_entry|
              victim = victim_entry[:target]
              models_hit = victim_entry[:models_hit].to_i
              next if victim[:current_health].to_i <= 0 || models_hit <= 0

              per_model = Phases::AttackResolution.damage(profile, victim, attack_type, vector, round_number)
              strike_damage = [ victim[:current_health].to_i, per_model * models_hit ].min
              next if strike_damage <= 0

              Phases::AttackResolution.record_missile_hit!(
                phase: phase,
                actor: actor,
                host: host,
                profile: profile,
                victim: victim,
                vector: vector,
                strike_damage: strike_damage,
                attack_type: attack_type,
                acting_side: acting_side,
                target_side: target_side,
                blockers: blockers,
                victims: victims,
                models_hit: models_hit
              )
            end
          end

          def expected_damage(actor, target, vector, round_number, attack_type, enemies)
            victims = attack_victims(actor, target, enemies)
            victims.sum do |victim|
              entry = victim[:target]
              per = Phases::AttackResolution.damage(actor, entry, attack_type == "magic" ? "magic" : "shooting", vector, round_number).to_f
              strike = per * victim[:models_hit].to_i
              models = [ entry[:models_remaining].to_i, 1 ].max
              capped = [ strike, entry[:current_health].to_f ].min
              capped * (1.0 + Math.log(models + 1, 10) * 0.15)
            end
          end
        end
      end
    end
  end
end
