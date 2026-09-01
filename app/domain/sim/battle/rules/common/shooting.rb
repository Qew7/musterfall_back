module Sim
  module Battle
    module Rules
      module Common
        module Shooting
          # rule: common | shooting | Default single-target ranged attack with hit roll and front-rank targeting.
          module_function

          def applies?(attacker, attack_type)
            kind = attack_type.to_s == "magic" ? attacker[:spell_template] : attacker[:shooting_template]
            kind.to_s == "common"
          end

          def attack_victims(_attacker, primary_target, _enemies)
            [ { target: primary_target, multiplier: 1 } ]
          end

          def template_descriptor(attacker, primary_target, victims)
            {
              shape: "line",
              kind: "common",
              start: { x: attacker[:x], y: attacker[:y] },
              end: { x: primary_target[:x], y: primary_target[:y] },
              affected_ids: victims.map { |entry| entry[:target][:entity_id] }
            }
          end

          def front_rank_models(host)
            return 1 if host[:kind].to_s == "hero"

            models = State.combatant_models_remaining(host)
            files = [ host[:files].to_i, 1 ].max
            [ files, models ].min
          end

          def missile_attacks_per_model(profile, host)
            [ profile[:missile_attacks] || host[:missile_attacks] || 1, 1 ].max
          end

          def shooting_attempts(host, profile)
            front_rank_models(host) * missile_attacks_per_model(profile, host)
          end

          def expected_damage(actor, target, vector, round_number, attack_type, enemies)
            attack = Phases::AttackResolution
            attack_victims(actor, target, enemies).sum do |entry|
              victim = entry[:target]
              attempts = shooting_attempts(actor, actor)
              chance = attack.hit_chance(actor, victim, "shooting")
              per_hit = attack.damage(actor, victim, attack_type, vector, round_number)
              attempts * chance * per_hit * entry[:multiplier].to_f
            end
          end

          def resolve_missile_strike!(phase:, actor:, host:, profile:, vector:, victims:, attack_type:, acting_side:, target_side:, round_number:, blockers:, rng:, terrain: [], **_extra)
            attack = Phases::AttackResolution
            victims.each do |victim_entry|
              victim = victim_entry[:target]
              next if victim[:current_health].to_i <= 0

              batch_actions = []
              attempts = 0
              hits = 0

              shooting_attempts(host, profile).times do
                break if victim[:current_health].to_i <= 0

                strike_damage = attack.damage(profile, victim, attack_type, vector, round_number)
                strike_damage = [ 1, (strike_damage * victim_entry[:multiplier].to_f).round ].max if victim_entry[:multiplier]
                next if strike_damage <= 0

                attempts += 1
                next unless attack.hit?(profile, victim, attack_type, rng, terrain: terrain)

                hits += 1
                batch_actions << attack.record_missile_hit!(
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
                  terrain: terrain,
                  defer_log: true
                )
              end

              miss_action = if hits <= 0 && attempts.positive?
                attack.build_missile_miss_action(
                  actor: actor,
                  host: host,
                  profile: profile,
                  victim: victim,
                  vector: vector,
                  attack_type: attack_type,
                  blockers: blockers,
                  victims: victims
                )
              end
              attack.finalize_strike_batch!(
                phase: phase,
                actions: batch_actions,
                attempts: attempts,
                hits: hits,
                actor: actor.merge(weapon_type: profile[:weapon_type] || actor[:weapon_type]),
                victim: victim,
                attack_type: attack_type,
                vector: vector,
                acting_side: acting_side,
                target_side: target_side,
                miss_action: miss_action
              )
            end
          end
        end
      end
    end
  end
end
