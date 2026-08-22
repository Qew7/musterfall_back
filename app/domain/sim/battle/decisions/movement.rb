module Sim
  module Battle
    module Decisions
      # Melee approach intents: who moves and toward which enemy.
      # Ability planners live under Rules::<rule>/movement.rb (Flying / Ground).
      module Movement
        CONTACT = Pathing::CONTACT
        CONTACT_SNAP = Geometry::Battlefield::CONFIG[:contact_snap]
        # Fight / stop-approaching band (closes the microscopic dead zone at CONTACT).
        ENGAGE = CONTACT + CONTACT_SNAP
        ADVANCING = { "rear" => "support", "support" => "front" }.freeze
        SLOT_RANK = { "front" => 0, "flank" => 1, "rear" => 2 }.freeze
        # Charge range and spend: ×MV. March is the same rate but straight-only.
        SETUP_RANGE_MV = 2.0

        module_function

        def flying?(combatant)
          Array(combatant[:abilities]).include?("flying")
        end

        def can_charge?(attacker, defender, terrain = [])
          Geometry::Battlefield.can_charge_through_terrain?(attacker, defender, terrain)
        end

        def planner_for(combatant)
          Rules.planner_for_movement(combatant)
        end

        def budget_for(combatant, enemies:)
          Rules.for(:movement).movement_budget(combatant, { enemies: enemies })
        end

        def charge_budget_for(combatant, enemies:)
          budget_for(combatant, enemies: enemies) * SETUP_RANGE_MV
        end

        def budget_meta(combatant, enemies:)
          Rules.for(:movement).movement_budget_meta(combatant, { enemies: enemies })
        end

        def melee_movers(combatants)
          Roles.active(combatants).select { |entry| Roles.melee_primary?(entry) || flying?(entry) }
        end

        # Only enemies inside the attacker's front arc are valid assault targets.
        def enemies_in_front_arc(combatant, enemies)
          Pathing.active_units(enemies).select do |entry|
            Geometry::Battlefield.in_front_arc?(combatant, entry, combatant[:facing])
          end
        end

        def chargeable_enemies(combatant, enemies, terrain = [])
          enemies_in_front_arc(combatant, enemies).select { |entry| can_charge?(combatant, entry, terrain) }
        end

        def nearest_enemy(combatant, enemies, terrain: [])
          candidates = chargeable_enemies(combatant, enemies, terrain)
          candidates = enemies_in_front_arc(combatant, enemies) if candidates.empty?
          return nil if candidates.empty?

          candidates.min_by { |entry| [ entry[:is_routing] ? 0 : 1, Geometry::Battlefield.distance_between_units(combatant, entry) ] }
        end

        def engaged?(combatant, enemy)
          return false unless enemy

          Geometry::Battlefield.distance_between_units(combatant, enemy) <= ENGAGE
        end

        def engaged_with_any?(combatant, enemies)
          Pathing.active_units(enemies).any? { |enemy| engaged?(combatant, enemy) }
        end

        def this_turn_charge?(combatant, enemy, enemies: [])
          return false unless enemy

          gap = Geometry::Battlefield.distance_between_units(combatant, enemy)
          gap <= budget_for(combatant, enemies: enemies) + ENGAGE
        end

        def within_charge_range?(combatant, enemy, enemies: [])
          return false unless enemy

          gap = Geometry::Battlefield.distance_between_units(combatant, enemy)
          gap <= charge_budget_for(combatant, enemies: enemies) + ENGAGE
        end

        def unclaimed_side(combatant, enemy, claimed)
          taken = claimed[enemy[:entity_id]]
          geo = Geometry::Battlefield.classify_attack_vector(combatant, enemy)
          ([ geo ] + %w[front flank rear]).uniq.find { |side| !taken.key?(side) }
        end

        def approach_mode_for(side, combatant, enemy)
          geo = Geometry::Battlefield.classify_attack_vector(combatant, enemy)
          return :direct if side == geo
          return :orbit_flank if side == "flank"
          return :wrap_rear if side == "rear"

          :direct
        end

        def row_advance_target(combatant, allies)
          target_row = ADVANCING[combatant[:row]]
          return nil unless target_row

          occupied = allies.any? do |entry|
            entry[:current_health].to_i > 0 &&
              entry[:entity_id] != combatant[:entity_id] &&
              entry[:lane] == combatant[:lane] &&
              entry[:row] == target_row
          end
          return nil if occupied

          target_row
        end

        # Flying wave first (leap landings), then Ground contact / flank waves.
        def plan_melee_waves(movers, enemies, terrain: [])
          living = Pathing.active_units(enemies)
          claimed = Hash.new { |hash, key| hash[key] = {} }
          grouped = movers.group_by { |combatant| planner_for(combatant) }

          [ Rules::Flying::Movement, Rules::Ground::Movement ].flat_map do |planner|
            planner.plan_waves(Array(grouped[planner]), living, claimed, terrain: terrain)
          end
        end

        def plan_melee_entries(movers, enemies, terrain: []) # leftovers:keep
          plan_melee_waves(movers, enemies, terrain: terrain).flat_map { |wave| wave[:entries] }
        end

        def build_entry(combatant, enemy, side, approach_mode, chargeable: true)
          {
            combatant: combatant,
            nearest: enemy,
            distance: Geometry::Battlefield.distance_between_units(combatant, enemy),
            vector: Geometry::Battlefield.classify_attack_vector(combatant, enemy),
            contact_slot: side,
            approach_mode: approach_mode,
            chargeable: chargeable
          }
        end

        def build_approach_intent(combatant:, nearest:, obstacles:, enemies: [], contact_slot: nil, allow_ally_bypass: false, approach_mode: :direct, terrain: [], chargeable: true)
          planner_for(combatant).build_approach_intent(
            combatant: combatant,
            nearest: nearest,
            obstacles: obstacles,
            enemies: enemies,
            contact_slot: contact_slot,
            allow_ally_bypass: allow_ally_bypass,
            approach_mode: approach_mode,
            terrain: terrain,
            chargeable: chargeable
          )
        end

        def front_alignment_to(combatant, enemy)
          Geometry::Battlefield.angle_between(enemy[:facing], enemy, combatant).to_f
        end

        def corner_contact_reachable?(origin, defender, budget, terrain: [])
          return false unless defender
          return true if engaged?(origin, defender)
          return false unless can_charge?(origin, defender, terrain)

          planner_for(origin).corner_contact_reachable?(origin, defender, budget, terrain: terrain)
        end
      end
    end
  end
end
