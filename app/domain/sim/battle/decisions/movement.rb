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

        # Sentinel so `march_meta` is only emitted when a caller sets it (ground
        # approach carries it; flying intents omit the key entirely).
        NO_MARCH_META = Object.new.freeze

        module_function

        # Shared "approach" intent hash built by the movement rules (ground / flying).
        # Pure data factory: each rule decides its own values and passes them in;
        # this must not branch on ability/flyer state.
        def approach_intent(combatant:, nearest:, plan:, budget:, destination:, contact_slot:, approach_mode:, charge_contact_id:, march_meta: NO_MARCH_META)
          intent = {
            kind: "approach",
            combatant: combatant,
            nearest: nearest,
            plan: plan,
            budget: budget
          }
          intent[:march_meta] = march_meta unless march_meta.equal?(NO_MARCH_META)
          intent.merge!(
            destination: destination,
            wait: false,
            contact_slot: contact_slot,
            approach_mode: approach_mode,
            charge_contact_id: charge_contact_id
          )
          intent
        end

        def flying?(combatant)
          Array(combatant[:abilities]).include?("flying")
        end

        def can_charge?(attacker, defender, terrain = [])
          Geometry::Battlefield.can_charge_through_terrain?(attacker, defender, terrain) ||
            Rules.for(:movement).can_charge_through_terrain?(attacker, defender, terrain)
        end

        def planner_for(combatant)
          Rules.planner_for_movement(combatant)
        end

        def budget_for(combatant, enemies:)
          Rules.for(:movement).movement_budget(combatant, { enemies: enemies })
        end

        def charge_budget_for(combatant, enemies:)
          ChargeRange.budget(combatant, enemies: enemies)
        end

        def budget_meta(combatant, enemies:)
          Rules.for(:movement).movement_budget_meta(combatant, { enemies: enemies })
        end

        def melee_movers(combatants)
          Roles.active(combatants).select do |entry|
            override = Rules.for(:movement).melee_mover?(entry)
            override.nil? ? Roles.melee_primary?(entry) || flying?(entry) : override
          end
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

          Geometry::Battlefield.melee_contact?(combatant, enemy)
        end

        def engaged_with_any?(combatant, enemies)
          Pathing.active_units(enemies).any? { |enemy| engaged?(combatant, enemy) }
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

        def approach_mode_for(_side, _combatant, _enemy)
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

        # Flyers move first, then nearby contacts, then the remaining ground units.
        def plan_movement_groups(movers, enemies, terrain: [], obstacles: [])
          living = Pathing.active_units(enemies)
          claimed = Hash.new { |hash, key| hash[key] = {} }
          grouped = movers.group_by { |combatant| planner_for(combatant) }

          [ Rules::Flying::Movement, Rules::Ground::Movement ].flat_map do |planner|
            planner.plan_groups(
              Array(grouped[planner]), living, claimed,
              terrain: terrain, obstacles: obstacles
            )
          end
        end

        def plan_melee_entries(movers, enemies, terrain: [], obstacles: []) # leftovers:keep
          plan_movement_groups(movers, enemies, terrain: terrain, obstacles: obstacles).flat_map { |group| group[:entries] }
        end

        # Give this unit the side if a path exists. Reserve it for others only
        # when a this-turn charge actually closes, or when this is just an approach.
        def reserve_side_if_reached(combatant, choice, claimed, obstacles:, enemies:, terrain:)
          nearest = choice[:nearest]
          slot = choice[:contact_slot].to_s
          return nil unless nearest && !slot.empty?
          return nil if claimed[nearest[:entity_id]].key?(slot)

          if Array(obstacles).empty?
            claimed[nearest[:entity_id]][slot] = combatant[:entity_id]
            return build_entry(
              combatant, nearest, slot, choice[:approach_mode] || :direct,
              chargeable: choice.fetch(:chargeable, true)
            )
          end

          intent = build_approach_intent(
            combatant: combatant,
            nearest: nearest,
            obstacles: obstacles,
            enemies: enemies,
            contact_slot: slot,
            approach_mode: choice[:approach_mode] || :direct,
            terrain: terrain,
            chargeable: choice.fetch(:chargeable, true)
          )
          return nil unless intent && !intent[:wait] && intent[:destination]

          pose = Geometry::Battlefield.merge_footprint(combatant, intent[:destination])
          reserve = if charge_reservation?(combatant, choice, enemies)
            Geometry::Battlefield.side_contact?(pose, nearest)
          else
            true
          end
          claimed[nearest[:entity_id]][slot] = combatant[:entity_id] if reserve

          build_entry(
            combatant, nearest, slot, choice[:approach_mode] || :direct,
            chargeable: choice.fetch(:chargeable, true)
          )
        end

        def charge_reservation?(combatant, choice, enemies)
          return false if %i[flyer_approach flyer_setup_rear flyer_setup_flank].include?(choice[:approach_mode]&.to_sym)
          return false unless choice.fetch(:chargeable, true)

          within_charge_range?(combatant, choice[:nearest], enemies: enemies)
        end

        def evict_stolen_sides!(entries_by_id, claimed)
          entries_by_id.delete_if do |entity_id, entry|
            owner = claimed[entry[:nearest][:entity_id]][entry[:contact_slot].to_s]
            owner && owner != entity_id
          end
        end

        def claimed_with(claimed, rejected)
          view = Hash.new { |hash, key| hash[key] = {} }
          claimed.each { |enemy_id, sides| view[enemy_id] = sides.dup }
          rejected.each do |enemy_id, sides|
            sides.each_key { |slot| view[enemy_id][slot.to_s] = true }
          end
          view
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

        def build_approach_intent(combatant:, nearest:, obstacles:, enemies: [], contact_slot: nil, approach_mode: :direct, terrain: [], chargeable: true)
          planner_for(combatant).build_approach_intent(
            combatant: combatant,
            nearest: nearest,
            obstacles: obstacles,
            enemies: enemies,
            contact_slot: contact_slot,
            approach_mode: approach_mode,
            terrain: terrain,
            chargeable: chargeable
          )
        end

        # Same target, other face; then another enemy. Wait only if nothing legal remains.
        def retarget_approach(combatant:, failed:, obstacles:, enemies:, terrain:, claimed_intents: [])
          claimed = Hash.new { |hash, key| hash[key] = {} }
          claimed_intents.each do |intent|
            next if intent[:wait]
            next if intent[:combatant][:entity_id] == combatant[:entity_id]

            nearest = intent[:nearest]
            slot = intent[:contact_slot]
            next unless nearest && slot

            claimed[nearest[:entity_id]][slot.to_s] = intent[:combatant][:entity_id]
          end

          blocked = failed[:nearest]
          if blocked
            failed_slot = failed[:contact_slot].to_s
            %w[front flank rear].each do |slot|
              next if slot == failed_slot
              next if claimed[blocked[:entity_id]].key?(slot)

              fresh = usable_approach(
                combatant: combatant,
                nearest: blocked,
                obstacles: obstacles,
                enemies: enemies,
                contact_slot: slot,
                approach_mode: failed[:approach_mode] || :direct,
                terrain: terrain,
                chargeable: failed.fetch(:chargeable, true)
              )
              return fresh if fresh
            end
            %w[front flank rear].each do |slot|
              claimed[blocked[:entity_id]][slot] = combatant[:entity_id]
            end
          end

          planner_for(combatant).plan_entries(
            [ combatant ], enemies, claimed, terrain: terrain, obstacles: obstacles
          ).each do |entry|
            fresh = usable_approach(
              combatant: combatant,
              nearest: entry[:nearest],
              obstacles: obstacles,
              enemies: enemies,
              contact_slot: entry[:contact_slot],
              approach_mode: entry[:approach_mode] || :direct,
              terrain: terrain,
              chargeable: entry.fetch(:chargeable, true)
            )
            return fresh if fresh
          end
          nil
        end

        def usable_approach(combatant:, nearest:, obstacles:, enemies:, contact_slot:, approach_mode:, terrain:, chargeable:)
          fresh = build_approach_intent(
            combatant: combatant,
            nearest: nearest,
            obstacles: obstacles,
            enemies: enemies,
            contact_slot: contact_slot,
            approach_mode: approach_mode,
            terrain: terrain,
            chargeable: chargeable
          )
          return nil unless fresh && !fresh[:wait] && fresh[:destination]

          traveled = Geometry::Battlefield.distance_between(combatant, fresh[:destination])
          turned = Geometry::Battlefield.shortest_facing_delta(combatant[:facing], fresh[:destination][:facing]).abs
          return nil unless traveled > 0.05 || turned > 0.05

          fresh.merge(
            nearest: nearest,
            contact_slot: contact_slot,
            approach_mode: approach_mode
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
