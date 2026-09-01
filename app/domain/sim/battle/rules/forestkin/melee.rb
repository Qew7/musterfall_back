module Sim
  module Battle
    module Rules
      module Forestkin
        module Melee
          # rule: forestkin | melee | Melee hit on target outside forest spawns forest terrain under target.
          module_function

          def after_hit!(ctx)
            host = ctx[:host] || ctx[:attacker]
            return unless Array(host[:abilities]).include?("forestkin")
            return unless ctx[:attack_type].to_s == "melee"

            defender = ctx[:defender]
            terrain = Array(ctx[:terrain])
            action = ctx[:action]
            return unless defender && action

            return if Geometry::Battlefield.in_forest?(defender, terrain)

            acting_side = ctx[:acting_side]
            target_side = ctx[:target_side]
            return unless acting_side && target_side

            all_combatants = acting_side[:combatants] + target_side[:combatants]
            feature = TerrainDelta.add!(
              terrain,
              action,
              type: "forest",
              x: defender[:x],
              y: defender[:y],
              all_combatants: all_combatants,
              allow_occupied: true
            )
            return unless feature

            ActionResult.append_clause!(action, "лес прорастает под #{defender[:name]}")
            action[:details] = Array(action[:details]) + [
              "forestkin terrain=#{feature[:id]} at=#{feature[:x].round(1)},#{feature[:y].round(1)}"
            ]
          end
        end
      end
    end
  end
end
