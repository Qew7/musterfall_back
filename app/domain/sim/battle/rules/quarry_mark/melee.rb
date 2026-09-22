module Sim
  module Battle
    module Rules
      module QuarryMark
        module Melee
          MARKS = 2
          PROVIDER = ->(profile) { Array(profile[:abilities]).include?("quarryMark") }
          SYNERGY = ArmySynergy.new(
            consumer: ->(profile) { !PROVIDER.call(profile) && (profile[:ranged].to_i.positive? || profile[:melee].to_i.positive?) },
            provider: PROVIDER,
            # Two marks are a finite planning capacity; this is not an aura.
            capacity: ->(profile) { profile[:models].to_f.positive? ? MARKS.to_f : 0.0 },
            range: ->(profile) { [ profile[:shooting_range].to_f / 2, 2.0 ].max }
          ).freeze

          # rule: quarry_mark | melee | The first two successful attacks mark a target; the next different allied attacker consumes it for one missed-hit reroll.
          module_function

          def army_synergies
            [ SYNERGY ]
          end

          def army_role(profile)
            :ranged if PROVIDER.call(profile)
          end

          def before_attack!(ctx)
            mark = ctx[:defender][:quarry_mark]
            host = ctx[:host]
            return unless usable_mark?(host, mark)

            ctx[:defender].delete(:quarry_mark)
            ctx[:quarry_reroll_available] = true
            log!(ctx, "#{host[:name]} используют метку на #{ctx[:defender][:name]}: один промах можно перебросить.", "consumed")
          end

          def usable_mark?(attacker, mark)
            mark && !attacker[:side_index].nil? && mark[:source_id] != (attacker[:host_id] || attacker[:entity_id]) &&
              mark[:side_index] == attacker[:side_index]
          end

          def missed_hit_rerolls(attacker, defender, _attack_type)
            usable_mark?(attacker, defender[:quarry_mark]) ? 1 : 0
          end

          def reroll_miss?(ctx)
            return false unless ctx.delete(:quarry_reroll_available)

            log!(ctx, "#{ctx[:host][:name]} перебрасывают промах по отмеченной добыче.", "reroll")
            true
          end

          def after_hit!(ctx)
            host = ctx[:host]
            return unless PROVIDER.call(ctx[:attacker]) && host[:quarry_marks_used].to_i < MARKS
            return if ctx[:action][:quarry_mark_processed]

            ctx[:action][:quarry_mark_processed] = true
            host[:quarry_marks_used] = host[:quarry_marks_used].to_i + 1
            target = ctx[:defender]
            return if target[:quarry_mark] || target[:current_health].to_f <= 0

            target[:quarry_mark] = { source_id: host[:entity_id], side_index: host[:side_index] }
            ctx[:action][:clauses] ||= []
            ctx[:action][:clauses] << "цель отмечена для союзников"
            ctx[:action][:details] << "quarry_mark source=#{host[:entity_id]} target=#{target[:entity_id]} used=#{host[:quarry_marks_used]}/#{MARKS}"
          end

          def log!(ctx, summary, result)
            ctx[:phase][:actions] << {
              type: "rule", actor_id: ctx[:host][:entity_id], actor_unit_id: ctx[:host][:entity_id],
              target_id: ctx[:defender][:entity_id], summary: summary,
              details: [ "quarry_mark result=#{result} rerolls=1" ],
              trace: Trace.build(rule_keys: [ "quarryMark" ], trigger: "attack", result: result, target_ids: [ ctx[:defender][:entity_id] ]),
              snapshot: State.snapshot_battlefield([ ctx[:acting_side], ctx[:target_side] ])
            }
            Phases::AttackResolution.add_event(ctx[:phase], summary)
          end
        end
      end
    end
  end
end
