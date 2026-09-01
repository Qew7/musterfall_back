module Sim
  module Battle
    module Rules
      module CorpseTrail
        module Shooting
          SUMMON_KIND = "zombies"
          SEARCH_RADIUS = 6.0

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
            seed = [ host[:entity_id], defender[:entity_id], center[:x], center[:y] ].join("-").hash.abs
            pose = SpellWorld.random_free_pose(
              Rng::Seeded.new(seed),
              unit: summon_stub(center),
              all_combatants: all_combatants,
              terrain: terrain,
              center: center,
              radius: SEARCH_RADIUS
            )
            return unless pose

            pose[:facing] = facing_toward_nearest_enemy(pose, target_side[:combatants])
            summoned = SpellWorld.summon!(side: acting_side, kind: SUMMON_KIND, pose: pose)
            action[:summon_ids] = Array(action[:summon_ids]) + [ summoned[:entity_id] ]
            ActionResult.append_clause!(action, "призван отряд «#{summoned[:name]}»")
            action[:details] = Array(action[:details]) + [
              "corpse_trail summon=#{summoned[:entity_id]} pose=#{pose[:x].round(1)},#{pose[:y].round(1)} facing=#{pose[:facing].round(1)}"
            ]
          end

          def summon_stub(center)
            profile = SpellWorld::SUMMONS.fetch(SUMMON_KIND)
            models = profile.fetch(:models)
            files = [ models, 3 ].min
            ranks = (models.to_f / files).ceil
            {
              x: center[:x],
              y: center[:y],
              facing: 0,
              frontage: files,
              files: files,
              ranks: ranks,
              model_width: 1.0,
              model_depth: 1.0,
              base_width: files.to_f,
              base_depth: ranks.to_f
            }
          end
          private_class_method :summon_stub

          def facing_toward_nearest_enemy(pose, enemies)
            nearest = Pathing.active_units(enemies).min_by do |enemy|
              Geometry::Battlefield.distance_between(pose, enemy)
            end
            return pose[:facing].to_f unless nearest

            Geometry::Battlefield.heading_to(pose, nearest)
          end
          private_class_method :facing_toward_nearest_enemy
        end
      end
    end
  end
end
