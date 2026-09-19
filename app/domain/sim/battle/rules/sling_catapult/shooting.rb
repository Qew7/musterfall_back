module Sim
  module Battle
    module Rules
      module SlingCatapult
        module Shooting
          # rule: sling_catapult | shooting | Consumes nearest slingFodder goblin within 6" to fire a blast shot.
          module_function

          FODDER_RANGE = 6.0
          CONSUMER = ->(profile) { Array(profile[:abilities]).include?("slingCatapult") }
          PROVIDER = ->(profile) { Array(profile[:abilities]).include?("slingFodder") }
          SYNERGY = ArmySynergy.new(
            consumer: CONSUMER, provider: PROVIDER,
            demand: ->(_profile) { Constants::MAX_BATTLE_ROUNDS.to_f },
            capacity: ->(profile) { profile[:models].to_f },
            range: ->(_profile) { FODDER_RANGE }, required: true
          ).freeze

          def army_synergies
            [ SYNERGY ]
          end

          def army_role(profile)
            return :artillery if CONSUMER.call(profile)
            :supply if PROVIDER.call(profile)
          end

          def before_play!(ctx)
            allies = ctx[:acting_side][:combatants]
            allies.each do |diver|
              diver.delete(:sling_catapult_fodder_id)
              next unless CONSUMER.call(diver)

              goblin = allies
                .select { |ally| PROVIDER.call(ally) && ally[:current_health].to_f.positive? }
                .select { |ally| Geometry::Battlefield.distance_between_units(diver, ally) <= FODDER_RANGE }
                .min_by { |ally| Geometry::Battlefield.distance_between_units(diver, ally) }
              diver[:sling_catapult_fodder_id] = goblin[:entity_id] if goblin
            end
          end

          def applies?(attacker, attack_type)
            attack_type.to_s == "shooting" &&
              Array(attacker[:abilities]).include?("slingCatapult") &&
              attacker[:sling_catapult_fodder_id].present?
          end

          def attack_victims(attacker, primary_target, enemies)
            Blast::Shooting.attack_victims(attacker, primary_target, enemies)
          end

          def template_descriptor(attacker, primary_target, victims)
            Blast::Shooting.template_descriptor(attacker, primary_target, victims).merge(kind: "slingCatapult")
          end

          def resolve_missile_strike!(phase:, actor:, host:, profile:, primary:, vector:, victims:, attack_type:, acting_side:, target_side:, round_number:, blockers:, rng:, terrain: [], **_extra)
            living = victims.select { |entry| entry[:target][:current_health].to_f.positive? }
            return if living.empty?

            goblin = acting_side[:combatants].find { |ally| ally[:entity_id] == host[:sling_catapult_fodder_id] }
            return unless goblin && goblin[:current_health].to_f.positive?

            consume_goblin!(phase, goblin, acting_side, target_side)
            living.each do |entry|
              victim = entry[:target]
              next unless victim[:current_health].to_f.positive?

              damage = Phases::AttackResolution.damage(profile, victim, attack_type, vector, round_number)
              damage = (damage * entry[:multiplier].to_f).round
              next if damage <= 0
              Phases::AttackResolution.record_missile_hit!(
                phase: phase, actor: actor, host: host, profile: profile, victim: victim,
                vector: vector, strike_damage: damage, attack_type: attack_type,
                acting_side: acting_side, target_side: target_side, blockers: blockers,
                victims: victims
              )
            end
          end

          def expected_damage(actor, target, vector, round_number, attack_type, enemies)
            Blast::Shooting.attack_victims(actor, target, enemies).sum do |entry|
              damage = Phases::AttackResolution.damage(actor, entry[:target], attack_type, vector, round_number)
              [ damage * entry[:multiplier].to_f, entry[:target][:current_health].to_f ].min
            end
          end

          def consume_goblin!(phase, goblin, acting_side, target_side)
            damage = [ goblin[:model_health].to_i, goblin[:current_health].to_f ].min
            before = State.snapshot_combatant(goblin)
            goblin[:current_health] -= damage
            State.sync_combatant_footprint!(goblin)
            summary = ActionResult.text_for(
              actor: { actor_name: goblin[:name], actor_role: "unit" },
              action: { type: "sling_catapult_ammo" },
              before: [ before ],
              after: [ State.snapshot_combatant(goblin) ],
              damage: damage,
              clauses: [ "#{goblin[:name]} отправляет одного расходника в полёт с Катапульты-камикадзе" ]
            )
            Phases::AttackResolution.add_event(phase, summary)
            phase[:actions] << {
              type: "sling_catapult_ammo",
              actor_id: goblin[:entity_id],
              actor_name: goblin[:name],
              damage: damage,
              summary: summary,
              details: [ "sling_fodder damage=#{damage}" ],
              trace: Trace.build(rule_keys: [ "slingCatapult", "slingFodder" ], trigger: "shooting", result: "consumed"),
              snapshot: State.snapshot_battlefield([ acting_side, target_side ])
            }
          end
          private_class_method :consume_goblin!
        end
      end
    end
  end
end
