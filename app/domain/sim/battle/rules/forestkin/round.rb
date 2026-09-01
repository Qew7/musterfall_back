module Sim
  module Battle
    module Rules
      module Forestkin
        module Round
          module_function

          def apply_passives!(side)
            terrain = Array(side[:terrain])
            side[:combatants].filter_map do |combatant|
              next unless Array(combatant[:abilities]).include?("forestkin")
              next unless Geometry::Battlefield.in_forest?(combatant, terrain)
              next unless combatant[:current_health].to_i.between?(1, combatant[:max_health].to_i - 1)

              before = State.snapshot_combatant(combatant)
              combatant[:current_health] += 1
              State.sync_combatant_footprint!(combatant)
              ActionResult.text_for(
                actor: {
                  actor_name: combatant[:name],
                  actor_role: combatant[:kind] == "hero" ? "hero" : "unit"
                },
                action: { type: "regen" },
                before: [ before ],
                after: [ State.snapshot_combatant(combatant) ],
                clauses: [ "регенерация в лесу" ],
                effects: [ { kind: "heal", amount: 1 } ]
              )
            end
          end
        end
      end
    end
  end
end
