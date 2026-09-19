require "digest"

module Sim
  module Battle
    module Rules
      module CorpseTrail
        module Shooting
          SUMMON_KIND = "zombies"
          SEARCH_RADIUS = 6.0

          # rule: corpse_trail | shooting | On hit, summons zombies on a clear pose near the victim (whole field if needed), facing the nearest enemy.
          module_function

          def after_hit!(ctx)
            host = ctx[:host] || ctx[:attacker]
            return unless Array(host[:abilities]).include?("corpseTrail")

            defender = ctx[:defender]
            acting_side = ctx[:acting_side]
            target_side = ctx[:target_side]
            action = ctx[:action]
            return unless defender && acting_side && target_side && action

            center = { x: defender[:x].to_f, y: defender[:y].to_f }
            all_combatants = acting_side[:combatants] + target_side[:combatants]
            terrain = Array(ctx[:terrain])
            seed = Digest::SHA256.hexdigest([ host[:entity_id], defender[:entity_id], center[:x], center[:y] ].join("-")).to_i(16)
            rng = Rng::Seeded.new(seed)
            pose = SpellWorld.random_free_pose(
              rng,
              unit: SpellWorld.summon_prototype(SUMMON_KIND, pose: center),
              all_combatants: all_combatants,
              terrain: terrain,
              center: center,
              radius: SEARCH_RADIUS,
              expand: true
            )
            return unless pose

            summoned = SpellWorld.summon!(
              side: acting_side,
              kind: SUMMON_KIND,
              pose: pose,
              all_combatants: all_combatants
            )
            living = acting_side[:combatants] + target_side[:combatants]
            unless SpellWorld.nudge_to_clear_pose!(
              summoned,
              rng: rng,
              all_combatants: living,
              terrain: terrain
            )
              acting_side[:combatants].delete(summoned)
              return
            end
            SpellWorld.face_nearest_enemy!(
              summoned, enemies: target_side[:combatants], all_combatants: living, terrain: terrain
            )
            action[:summon_ids] = Array(action[:summon_ids]) + [ summoned[:entity_id] ]
            ActionResult.append_clause!(action, "призван отряд «#{summoned[:name]}»")
            action[:details] = Array(action[:details]) + [
              "corpse_trail summon=#{summoned[:entity_id]} pose=#{summoned[:x].round(1)},#{summoned[:y].round(1)} facing=#{summoned[:facing].round(1)}"
            ]
          end
        end
      end
    end
  end
end
