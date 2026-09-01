module Sim
  module Battle
    module Rules
      module MagicEffects
        module Movement
          # rule: magic_effects | movement | ranged_hindered halves move; after_move effects damage movers.
          module_function

          def movement_multiplier(combatant, _ctx)
            return 1.0 unless Array(combatant[:abilities]).include?("flying")
            return 1.0 unless Sim::Battle::SpellEffects.status?(combatant, :ranged_hindered)

            0.5
          end

          def after_play!(ctx)
            moved_ids = ctx[:phase][:actions].filter_map do |action|
              next unless action[:type] == "movement"
              next unless Geometry::Battlefield.distance_between(action[:from], action[:to]) > 0.05

              action[:actor_id]
            end.uniq
            ctx[:acting_side][:combatants].each do |combatant|
              next unless moved_ids.include?(combatant[:entity_id])

              Sim::Battle::SpellEffects.triggers(combatant, :after_move).each do |effect, payload|
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
        end
      end
    end
  end
end
