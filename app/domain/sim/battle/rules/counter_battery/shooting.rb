module Sim
  module Battle
    module Rules
      module CounterBattery
        module Shooting
          AMMUNITION = 2
          STRUCTURAL_DAMAGE = 6

          # rule: counter_battery | shooting | Two single structural shots against machines that have fired; a hit jams the next enemy shooting phase.
          module_function

          def army_role(profile)
            :artillery if Array(profile[:abilities]).include?("counterBattery")
          end

          def applies?(profile, attack_type)
            attack_type.to_s == "shooting" && Array(profile[:abilities]).include?("counterBattery")
          end

          def special_shot?(profile, target)
            applies?(profile, "shooting") && profile[:counter_battery_shots].to_i < AMMUNITION &&
              Array(target[:abilities]).include?("machine") && target[:has_fired]
          end

          def prioritize_targets(attacker, targets, attack_type)
            return targets unless applies?(attacker, attack_type)

            machines = targets.select { |target| special_shot?(attacker, target) }
            machines.empty? ? targets : machines
          end

          def allow_attack?(attacker, ctx = nil)
            return true if ctx && ctx[:attack_type].to_s != "shooting"

            !attacker[:counter_battery_jammed]
          end

          def after_play!(ctx)
            Array(ctx.dig(:acting_side, :combatants)).each do |combatant|
              combatant.delete(:counter_battery_jammed)
            end
          end

          def after_attack!(ctx)
            return unless ctx[:attack_type].to_s == "shooting"
            return unless Array(ctx[:actions]).any? do |action|
              action[:type] == "shooting" &&
                (action[:attacks_attempted].to_i.positive? || action[:target_state_before])
            end

            ctx[:host][:has_fired] = true
          end

          def fractional_damage?(_profile, _attack_type)
            true
          end

          def attack_victims(attacker, target, enemies)
            Common::Shooting.attack_victims(attacker, target, enemies)
          end

          def template_descriptor(attacker, target, victims)
            Common::Shooting.template_descriptor(attacker, target, victims)
          end

          def expected_damage(actor, target, vector, round_number, attack_type, enemies)
            return Common::Shooting.expected_damage(actor, target, vector, round_number, attack_type, enemies) unless special_shot?(actor, target)

            Phases::AttackResolution.hit_chance(actor, target, "shooting") *
              [ STRUCTURAL_DAMAGE, target[:current_health].to_i ].min
          end

          def resolve_missile_strike!(**ctx)
            target = ctx[:primary] || ctx[:victims].first[:target]
            return Common::Shooting.resolve_missile_strike!(**ctx) unless special_shot?(ctx[:host], target)

            attack = Phases::AttackResolution
            host = ctx[:host]
            host[:counter_battery_shots] = host[:counter_battery_shots].to_i + 1
            hit = attack.hit?(ctx[:profile], target, "shooting", ctx[:rng], terrain: ctx[:terrain] || [])
            shared = ctx.slice(:phase, :actor, :host, :profile, :vector, :attack_type, :acting_side, :target_side, :blockers, :victims)
            actions = []
            if hit
              target[:counter_battery_jammed] = true
              actions << attack.record_missile_hit!(
                **shared, victim: target, strike_damage: STRUCTURAL_DAMAGE,
                hits_landed: 1, attacks_attempted: 1, defer_log: true, terrain: ctx[:terrain] || []
              )
              actions.last[:clauses] = Array(actions.last[:clauses]) + [ "контрбатарейный выстрел: следующая стрельба цели сорвана" ]
              actions.last[:details] = Array(actions.last[:details]) + [ "counter_battery ammunition=#{AMMUNITION - host[:counter_battery_shots]} structural_damage=#{STRUCTURAL_DAMAGE}" ]
            end
            miss = unless hit
              attack.build_missile_miss_action(**shared.except(:phase, :acting_side, :target_side), victim: target)
            end
            attack.finalize_strike_batch!(
              **ctx.slice(:phase, :actor, :vector, :attack_type, :acting_side, :target_side),
              actions: actions, attempts: 1, hits: hit ? 1 : 0, victim: target, miss_action: miss
            )
          end
        end
      end
    end
  end
end
