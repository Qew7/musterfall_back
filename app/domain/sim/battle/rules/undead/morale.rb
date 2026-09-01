module Sim
  module Battle
    module Rules
      module Undead
        module Morale
          # rule: undead | morale | Morale failure chips HP by failure_margin×model_health (hero: margin only) instead of routing.
          module_function

          def handle_morale_failure!(combatant, check, _ctx)
            return false unless Array(combatant[:abilities]).include?("undead")

            before = State.snapshot_combatant(combatant)
            margin = check[:failure_margin].to_i
            model_health = [ combatant[:model_health].to_i, 1 ].max
            damage = if combatant[:kind] == "hero"
              [ margin, combatant[:current_health].to_i ].min
            else
              [ margin * model_health, combatant[:current_health].to_i ].min
            end
            combatant[:current_health] = [ 0, combatant[:current_health] - damage ].max
            State.sync_combatant_footprint!(combatant)
            clause = if combatant[:kind] == "hero"
              "#{combatant[:name]} проваливает проверку морали и теряет #{damage} здоровья вместо бегства"
            elsif damage >= before[:current_health].to_i
              "#{combatant[:name]} проваливает проверку морали и рассыпается"
            else
              models_lost = damage / model_health
              "#{combatant[:name]} проваливает проверку морали и теряет #{models_lost} моделей вместо бегства"
            end
            summary = ActionResult.text_for(
              actor: {
                actor_name: combatant[:name],
                actor_role: combatant[:kind] == "hero" ? "hero" : "unit"
              },
              action: { type: "morale" },
              before: [ before ],
              after: [ State.snapshot_combatant(combatant) ],
              damage: damage,
              clauses: [ clause ]
            )
            { damage: damage, summary: summary }
          end
        end
      end
    end
  end
end
