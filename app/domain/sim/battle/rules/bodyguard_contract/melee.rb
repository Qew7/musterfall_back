module Sim
  module Battle
    module Rules
      module BodyguardContract
        module Melee
          RANGE = 2.0
          MAX_DAMAGE = 3
          PROVIDER = ->(profile) { Array(profile[:abilities]).include?("bodyguardContract") }
          CONSUMER = ->(profile) { %w[unit hero].include?(profile[:kind]) }
          SYNERGY = ArmySynergy.new(
            consumer: CONSUMER, provider: PROVIDER,
            capacity: ->(profile) { [ profile[:models].to_f, 1.0 ].min },
            range: ->(_profile) { RANGE }
          ).freeze

          # rule: bodyguard_contract | melee | Once per battle, a nearby standing guard takes up to 3 actual incoming allied damage without further mitigation.
          module_function

          def army_synergies
            [ SYNERGY ]
          end

          def army_role(profile)
            :frontline if PROVIDER.call(profile)
          end

          def before_damage!(ctx)
            victim = ctx[:defender]
            return unless ctx[:damage].to_f.positive?

            guard = Array(ctx.dig(:target_side, :combatants)).select do |ally|
              PROVIDER.call(ally) && ally[:entity_id] != victim[:entity_id] &&
                ally[:current_health].to_f.positive? && !ally[:is_routing] && !ally[:bodyguard_contract_used] &&
                Geometry::Battlefield.distance_between_units(ally, victim) <= RANGE
            end.min_by { |ally| [ Geometry::Battlefield.distance_between_units(ally, victim), ally[:entity_id].to_s ] }
            return unless guard

            before = State.snapshot_combatant(guard)
            damage = [ MAX_DAMAGE, ctx[:damage], guard[:current_health] ].min
            guard[:bodyguard_contract_used] = true
            guard[:current_health] -= damage
            ctx[:damage] -= damage
            State.sync_combatant_footprint!(guard)
            summary = "#{guard[:name]} принимают на себя #{damage.to_i} урона, прикрывая #{victim[:name]}."
            action = {
              type: ctx[:attack_type], actor_id: ctx[:attacker][:entity_id],
              actor_unit_id: ctx[:host][:entity_id], actor_name: ctx[:attacker][:name],
              target_id: guard[:entity_id], target_name: guard[:name], damage: damage,
              target_state_before: before, target_state_after: State.snapshot_combatant(guard),
              protected_id: victim[:entity_id], summary: summary,
              details: [ "bodyguard_contract protected=#{victim[:entity_id]} provider=#{guard[:entity_id]} redirected=#{damage} used=true" ],
              trace: Trace.build(rule_keys: [ "bodyguardContract" ], trigger: "before_damage", result: "redirected", target_ids: [ guard[:entity_id], victim[:entity_id] ]),
              snapshot: State.snapshot_battlefield([ ctx[:acting_side], ctx[:target_side] ])
            }
            ctx[:phase][:actions] << action
            Phases::AttackResolution.add_event(ctx[:phase], summary)
          end
        end
      end
    end
  end
end
