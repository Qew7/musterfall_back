module Sim
  module Battle
    module Rules
      module MagicEffects
        # rule: magic_effects | shared | Applies spell-effect trigger damage and logs magic actions.
        module_function

        def trigger_damage!(phase:, target:, effect:, payload:, sides:)
          damage = [ payload[:damage].to_i, target[:current_health].to_i ].min
          return if damage <= 0

          before = State.snapshot_combatant(target)
          target[:current_health] -= damage
          State.sync_combatant_footprint!(target)
          spell_key = payload[:spell_key] || effect[:key]
          spell_name = Spells.fetch(spell_key)&.name || spell_key.to_s.tr("_", " ")
          summary = ActionResult.text_for(
            actor: { actor_name: target[:name], actor_role: target[:kind] == "hero" ? "hero" : "unit" },
            action: { type: "spell_effect" },
            before: [ before ],
            after: [ State.snapshot_combatant(target) ],
            damage: damage,
            clauses: [ "#{target[:name]} получает #{damage} урона от эффекта «#{spell_name}»" ]
          )
          action = {
            type: "magic",
            outcome: "triggered",
            target_id: target[:entity_id],
            target_name: target[:name],
            damage: damage,
            affected_ids: [ target[:entity_id] ],
            target_state_before: before,
            target_state_after: State.snapshot_combatant(target),
            summary: summary,
            details: [ "spell_effect=#{spell_key} damage=#{damage}" ],
            trace: Trace.build(
              rule_keys: [ spell_key ],
              trigger: "spell_effect",
              result: "damage",
              target_ids: [ target[:entity_id] ]
            ),
            snapshot: State.snapshot_battlefield(sides)
          }
          phase[:actions] << action
          Phases::AttackResolution.add_event(phase, summary)
          action
        end
      end
    end
  end
end
