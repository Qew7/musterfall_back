module Sim
  module Battle
    module Rules
      module Poison
        module Melee
          # rule: poison | melee | Multi-wound non-machine: extra model kill after hit. 1W/machine: normal strike damage only.
          module_function

          def after_hit!(ctx)
            defender = ctx[:defender]
            return unless poison_attacker?(ctx)
            return if Array(defender[:abilities]).include?("undead")
            return if defender[:current_health].to_i <= 0

            action = ctx[:action]
            return if action[:poison_model_applied]
            return if strike_killed_model?(action, defender)

            model_health = [ defender[:model_health].to_i, 1 ].max
            machine = machine_defender?(defender)
            return if model_health <= 1 || machine

            damage = [ model_health, defender[:current_health].to_i ].min
            return if damage <= 0

            action[:poison_model_applied] = true
            defender[:current_health] -= damage
            State.sync_combatant_footprint!(defender)
            action[:damage] = action[:damage].to_i + damage
            action[:target_state_after] = State.snapshot_combatant(defender)
            action[:snapshot] = State.snapshot_battlefield([ ctx[:acting_side], ctx[:target_side] ])
            (action[:details] ||= []) << "poison_model_kill damage=#{damage}"
            ActionResult.append_clause!(action, "яд убивает одну модель")
          end

          def poison_attacker?(ctx)
            [ ctx[:attacker], ctx[:host] ].compact.any? { |entry| Array(entry[:abilities]).include?("poison") }
          end
          private_class_method :poison_attacker?

          def machine_defender?(defender)
            Array(defender[:abilities]).include?("machine") || defender[:model_class].to_s == "machine"
          end
          private_class_method :machine_defender?

          def strike_killed_model?(action, defender)
            before = action[:target_state_before]
            return false unless before

            models_before = before[:models_remaining].to_i
            models_now = State.combatant_models_remaining(defender)
            models_before - models_now >= 1
          end
          private_class_method :strike_killed_model?
        end
      end
    end
  end
end
