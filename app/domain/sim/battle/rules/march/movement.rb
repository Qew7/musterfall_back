module Sim
  module Battle
    module Rules
      module March
        # Ground units march at ×MV when no enemy sits within clearance of their tray edges.
        module Movement
          # rule: march | movement | Ground units (not flying/machine/undead) get march move when no enemy in clearance.
          module_function

          def applies?(combatant)
            abilities = Array(combatant[:abilities])
            !abilities.include?("flying") && !abilities.include?("machine") && !abilities.include?("undead")
          end

          def movement_multiplier(_combatant, _ctx)
            1.0
          end

          def movement_budget_meta(combatant, ctx)
            return {} unless applies?(combatant)

            clearance = CONFIG[:march_clearance_inches].to_f
            if SpellEffects.status?(combatant, :no_march)
              return {
                march: "blocked",
                march_clearance: clearance,
                march_blocker_name: "магические путы"
              }
            end
            blocker = nearest_blocker(combatant, ctx[:enemies], clearance: clearance)
            if blocker
              {
                march: "blocked",
                march_clearance: clearance,
                march_blocker_id: blocker[:entity_id],
                march_blocker_name: blocker[:name],
                march_blocker_dist: blocker[:distance]
              }
            else
              {
                march: "active",
                march_clearance: clearance,
                march_multiplier: CONFIG[:march_multiplier].to_f
              }
            end
          end

          def nearest_blocker(combatant, enemies, clearance:)
            enemy = Geometry::Battlefield.nearest_enemy_within_tray_clearance(
              combatant,
              enemies,
              clearance: clearance
            )
            return nil unless enemy

            enemy.merge(
              distance: Geometry::Battlefield.distance_between_units(combatant, enemy)
            )
          end

          CONFIG = Geometry::Battlefield::CONFIG
        end
      end
    end
  end
end
