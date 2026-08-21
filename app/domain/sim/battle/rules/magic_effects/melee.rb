module Sim
  module Battle
    module Rules
      module MagicEffects
        module Melee
          module_function

          def after_hit!(ctx)
            Sim::Battle::SpellEffects.triggers(ctx[:defender], :after_melee_hit).each do |effect, payload|
              MagicEffects.trigger_damage!(
                phase: ctx[:phase],
                target: ctx[:attacker],
                effect: effect,
                payload: payload,
                sides: [ ctx[:acting_side], ctx[:target_side] ]
              )
            end
          end
        end
      end
    end
  end
end
