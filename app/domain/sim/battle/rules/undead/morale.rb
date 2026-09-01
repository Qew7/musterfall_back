module Sim
  module Battle
    module Rules
      module Undead
        module Morale
          module_function

          def handle_morale_failure!(combatant, check, _ctx)
            return false unless Array(combatant[:abilities]).include?("undead")

            before = State.snapshot_combatant(combatant)
            damage = combatant[:kind] == "hero" ? check[:failure_margin].to_i : combatant[:current_health].to_i
            combatant[:current_health] = [ 0, combatant[:current_health] - damage ].max
            State.sync_combatant_footprint!(combatant)
            clause = if combatant[:kind] == "hero"
              "#{combatant[:name]} проваливает проверку морали и теряет #{damage} здоровья вместо бегства"
            else
              "#{combatant[:name]} проваливает проверку морали и рассыпается"
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
