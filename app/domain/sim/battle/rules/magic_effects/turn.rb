module Sim
  module Battle
    module Rules
      module MagicEffects
        module Turn
          module_function

          def before_play!(ctx)
            trigger!(ctx, :start_turn)
          end

          def after_play!(ctx)
            trigger!(ctx, :end_turn)
          end

          def trigger!(ctx, event)
            ctx[:acting_side][:combatants].each do |combatant|
              Sim::Battle::SpellEffects.triggers(combatant, event).each do |effect, payload|
                MagicEffects.trigger_damage!(
                  phase: ctx[:phase],
                  target: combatant,
                  effect: effect,
                  payload: payload,
                  sides: [ ctx[:acting_side], ctx[:target_side] ]
                )
              end
            end
          end
          private_class_method :trigger!
        end
      end
    end
  end
end
