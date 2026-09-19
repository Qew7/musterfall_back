module Sim
  module Battle
    module Rules
      module Regen
        module Round
          # rule: regen | round | d6 3+ heals +2 HP each round while wounded.
          module_function

          HEAL_AMOUNT = 2
          PROC_TARGET = 3 # d6 3+ (~67%)

          def apply_passives!(side)
            rng = side[:rng]
            side[:combatants].filter_map do |combatant|
              next unless Array(combatant[:abilities]).include?("regen")
              next unless combatant[:current_health].to_f.positive? && combatant[:current_health].to_f < combatant[:max_health].to_f
              next unless regen_proc?(rng)

              before = State.snapshot_combatant(combatant)
              combatant[:current_health] = [ combatant[:current_health].to_f + HEAL_AMOUNT, combatant[:max_health].to_i ].min
              State.sync_combatant_footprint!(combatant)
              ActionResult.text_for(
                actor: {
                  actor_name: combatant[:name],
                  actor_role: combatant[:kind] == "hero" ? "hero" : "unit"
                },
                action: { type: "regen" },
                before: [ before ],
                after: [ State.snapshot_combatant(combatant) ],
                clauses: [ "регенерация +#{HEAL_AMOUNT}" ],
                effects: [ { kind: "heal", amount: HEAL_AMOUNT } ]
              )
            end
          end

          def regen_proc?(rng)
            return true unless rng

            rng.rand(6) + 1 >= PROC_TARGET
          end
          private_class_method :regen_proc?
        end
      end
    end
  end
end
