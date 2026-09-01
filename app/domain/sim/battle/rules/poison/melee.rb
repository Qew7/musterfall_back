module Sim
  module Battle
    module Rules
      module Poison
        module Melee
          module_function

          def after_hit!(ctx)
            defender = ctx[:defender]
            return unless [ ctx[:attacker], ctx[:host] ].compact.any? { |entry| Array(entry[:abilities]).include?("poison") }
            return if Array(defender[:abilities]).include?("undead")
            return if defender[:current_health].to_i <= 0

            damage = [ defender[:model_health].to_i, defender[:current_health].to_i ].min
            defender[:current_health] -= damage
            State.sync_combatant_footprint!(defender)
            action = ctx[:action]
            action[:damage] = action[:damage].to_i + damage
            action[:target_state_after] = State.snapshot_combatant(defender)
            action[:snapshot] = State.snapshot_battlefield([ ctx[:acting_side], ctx[:target_side] ])
            (action[:details] ||= []) << "poison_model_kill damage=#{damage}"
            ActionResult.append_clause!(action, "яд убивает одну модель")
          end
        end
      end
    end
  end
end
