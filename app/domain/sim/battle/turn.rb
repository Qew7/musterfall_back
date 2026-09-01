module Sim
  module Battle
    module Turn
      module_function

      # Phase order: start morale → movement → magic/shooting (planned after move) → melee.
      def play(round_number:, acting_side:, target_side:, rng:, terrain: [])
        SpellEffects.expire!([ acting_side, target_side ], moment: :start_turn, side_key: acting_side[:side_key])
        expired_start = SpellWorld.expire_terrain!(terrain, moment: :start_turn, side_key: acting_side[:side_key])
        context = {
          round_number: round_number,
          acting_side: acting_side,
          target_side: target_side,
          rng: rng,
          terrain: terrain
        }
        sides = [ acting_side, target_side ]
        start_phase = Phases::Morale.play_start(**context)
        record_terrain_expiry!(start_phase, expired_start, sides, prepend: true)
        movement_phase = Phases::Movement.play(**context)
        missile_plan = Phases::Missile.plan(**context)
        context = context.merge(missile_plan: missile_plan)
        result = {
          player_id: acting_side[:player_id],
          player_name: acting_side[:player_name],
          phases: [
            start_phase,
            movement_phase,
            Phases::Magic.play(**context),
            Phases::Shooting.play(**context),
            Phases::Melee.play(**context)
          ]
        }
        Rules.for(:turn).after_play!(context.merge(phase: result[:phases].last))
        SpellEffects.expire!([ acting_side, target_side ], moment: :end_turn, side_key: acting_side[:side_key])
        expired_end = SpellWorld.expire_terrain!(terrain, moment: :end_turn, side_key: acting_side[:side_key])
        vanished = State.tick_summons!(sides)
        record_terrain_expiry!(result[:phases].last, expired_end, sides)
        record_summon_expiry!(result[:phases].last, vanished, sides)
        result
      end

      def record_terrain_expiry!(phase, removed, sides, prepend: false)
        return if Array(removed).empty?

        names = removed.map { |feature| feature[:name].presence || feature[:type] }
        summary = names.size == 1 ? "С поля исчезает #{names.first}." : "С поля исчезает ландшафт заклинаний: #{names.join(', ')}."
        delta = []
        removed.each { |feature| TerrainDelta.append!(delta, :remove, feature) }
        record_expiry_action!(
          phase,
          sides,
          summary: summary,
          details: removed.map do |feature|
            "terrain remove id=#{feature[:id]} type=#{feature[:type]} x=#{feature[:x]} y=#{feature[:y]} reason=expire"
          end,
          terrain_delta: delta,
          rule_keys: [ "terrain" ],
          prepend: prepend
        )
      end
      private_class_method :record_terrain_expiry!

      def record_summon_expiry!(phase, vanished, sides)
        return if Array(vanished).empty?

        names = vanished.map { |combatant| combatant[:name] }
        summary = names.size == 1 ? "#{names.first} растворяется." : "Призванные растворяются: #{names.join(', ')}."
        record_expiry_action!(
          phase,
          sides,
          summary: summary,
          details: vanished.map { |combatant| "summon expire id=#{combatant[:entity_id]} kind=#{combatant[:summon_kind]}" },
          summon_ids: vanished.map { |combatant| combatant[:entity_id] },
          rule_keys: [ "summon" ]
        )
      end
      private_class_method :record_summon_expiry!

      def record_expiry_action!(phase, sides, summary:, details:, rule_keys:, terrain_delta: [], summon_ids: [], prepend: false)
        action = {
          type: "magic",
          outcome: "expired",
          terrain_delta: terrain_delta,
          affected_ids: summon_ids,
          effects: [],
          summon_ids: summon_ids,
          summary: summary,
          details: details,
          snapshot: State.snapshot_battlefield(sides),
          trace: Trace.build(rule_keys: rule_keys, trigger: "spell_expire", result: "remove")
        }
        if prepend
          phase[:actions].unshift(action)
          phase[:events].unshift(summary)
        else
          phase[:actions] << action
          Phases::AttackResolution.add_event(phase, summary)
        end
      end
      private_class_method :record_expiry_action!
    end
  end
end
