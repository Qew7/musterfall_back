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

          def fractional_damage?(_profile, attack_type)
            attack_type.to_s == "shooting"
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

          def expected_damage(actor, target, vector, round_number, attack_type, enemies, victims: nil)
            attack = Phases::AttackResolution
            (victims || attack_victims(actor, target, enemies)).sum do |entry|
              victim = entry[:target]
              attempts = shooting_attempts(actor, actor)
              chance = attack.hit_chance(actor, victim, "shooting")
              per_hit = attack.damage(actor, victim, attack_type, vector, round_number)
              rerolls = Rules.for(:shooting).missed_hit_rerolls(actor, victim, attack_type)
              expected_volley_damage(attempts, chance, per_hit * entry[:multiplier].to_f, victim[:current_health], rerolls: rerolls)
            end
          end

          # E[floor(hits * damage)], not floor(E[hits] * damage).
          def expected_volley_damage(attempts, chance, per_hit, health, rerolls: 0)
            probabilities = [ 1.0 ]
            attempts.times do
              next_probabilities = Array.new(probabilities.size + 1, 0.0)
              probabilities.each_with_index do |probability, hits|
                next_probabilities[hits] += probability * (1 - chance)
                next_probabilities[hits + 1] += probability * chance
              end
              probabilities = next_probabilities
            end
            probabilities.each_with_index.sum do |probability, hits|
              base = [ (hits * per_hit).floor, health ].min
              # One marked miss may reroll; a perfect volley has no failed die.
              if rerolls.positive? && hits < attempts
                improved = [ ((hits + 1) * per_hit).floor, health ].min
                probability * (base * (1 - chance) + improved * chance)
              else
                probability * base
              end
            end
          end

          def resolve_missile_strike!(phase:, actor:, host:, profile:, vector:, victims:, attack_type:, acting_side:, target_side:, round_number:, blockers:, rng:, terrain: [], **_extra)
            attack = Phases::AttackResolution
            victims.each do |victim_entry|
              victim = victim_entry[:target]
              next if victim[:current_health].to_f <= 0

              batch_actions = []
              attempts = 0
              hits = 0
              total_damage = 0.0
              strike_damage = attack.damage(profile, victim, attack_type, vector, round_number)
              if victim_entry[:multiplier]
                strike_damage *= victim_entry[:multiplier].to_f
                strike_damage = [ 1, strike_damage.round ].max unless fractional_damage?(profile, attack_type)
              end
              next unless strike_damage.positive?

              hit_context = {
                phase: phase, attacker: profile, host: host, defender: victim,
                acting_side: acting_side, target_side: target_side, attack_type: attack_type, terrain: terrain
              }
              Rules.for(Rules.damage_phase_for(attack_type)).before_attack!(hit_context)
              shooting_attempts(host, profile).times do
                attempts += 1
                next unless attack.hit?(profile, victim, attack_type, rng, terrain: terrain, context: hit_context)

                hits += 1
                total_damage += strike_damage
              end

              # Resolve one simultaneous volley per victim, with one damage
              # action. Discard the remainder per target; never carry wounds
              # smaller than one HP into another attack or another round.
              if hits.positive?
                batch_actions << attack.record_missile_hit!(
                  phase: phase,
                  actor: actor,
                  host: host,
                  profile: profile,
                  victim: victim,
                  vector: vector,
                  strike_damage: total_damage.floor,
                  hits_landed: hits,
                  attacks_attempted: attempts,
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
