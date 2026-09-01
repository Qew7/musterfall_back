module Sim
  module Battle
    module Templates
      # Shared per-model template strike logic: hit count, damage cap, resolve, AI estimate.
      class Base
        attr_reader :attacker, :primary_target

        def initialize(attacker, primary_target)
          @attacker = attacker
          @primary_target = primary_target
        end

        def attack_victims(enemies)
          living_enemies(enemies).filter_map do |entry|
            count = models_hit(entry)
            next if count <= 0

            build_victim_entry(entry, count)
          end
        end

        def models_hit(unit)
          raise NotImplementedError
        end

        def template_descriptor(_victims)
          raise NotImplementedError
        end

        def expected_damage(actor, _target, vector, round_number, attack_type, enemies)
          attack_victims(enemies).sum do |entry|
            per = Phases::AttackResolution.damage(actor, entry[:target], attack_type, vector, round_number)
            strike_damage(entry[:target], entry[:models_hit], per)
          end
        end

        def resolve_missile_strike!(phase:, actor:, host:, profile:, vector:, victims:, attack_type:, acting_side:, target_side:, round_number:, blockers:, **_extra)
          victims.each do |entry|
            victim = entry[:target]
            models_hit = entry[:models_hit].to_i
            next if victim[:current_health].to_i <= 0 || models_hit <= 0

            per_model = Phases::AttackResolution.damage(profile, victim, attack_type, vector, round_number)
            damage = strike_damage(victim, models_hit, per_model)
            next if damage <= 0

            Phases::AttackResolution.record_missile_hit!(
              phase: phase,
              actor: actor,
              host: host,
              profile: profile,
              victim: victim,
              vector: vector,
              strike_damage: damage,
              attack_type: attack_type,
              acting_side: acting_side,
              target_side: target_side,
              blockers: blockers,
              victims: victims,
              models_hit: models_hit
            )
          end
        end

        def strike_damage(victim, models_hit, per_model)
          count = models_hit.to_i
          return 0 if count <= 0

          raw = per_model.to_i * count
          cap = count * [ victim[:model_health].to_i, 1 ].max
          [ raw, cap, victim[:current_health].to_i ].min
        end

        protected

        def living_enemies(enemies)
          enemies.select { |entry| entry[:current_health].to_i > 0 }
        end

        def build_victim_entry(entry, models_hit, **extra)
          { target: entry, models_hit: models_hit, **extra }
        end
      end
    end
  end
end
