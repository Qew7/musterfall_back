module Sim
  module Battle
    module Decisions
      # Melee approach intents: who moves and toward which enemy.
      module Movement
        CONTACT = Pathing::CONTACT
        CONTACT_SNAP = Geometry::Battlefield::CONFIG[:contact_snap]
        # Fight / stop-approaching band (closes the microscopic dead zone at CONTACT).
        ENGAGE = CONTACT + CONTACT_SNAP
        ADVANCING = { "rear" => "support", "support" => "front" }.freeze
        SLOT_RANK = { "front" => 0, "flank" => 1, "rear" => 2 }.freeze

        module_function

        def melee_movers(combatants)
          Roles.active(combatants).select { |entry| Roles.melee_primary?(entry) }
        end

        # Only enemies inside the attacker's front arc are valid assault targets.
        def enemies_in_front_arc(combatant, enemies)
          Pathing.active_units(enemies).select do |entry|
            Geometry::Battlefield.in_front_arc?(combatant, entry, combatant[:facing])
          end
        end

        def nearest_enemy(combatant, enemies)
          candidates = enemies_in_front_arc(combatant, enemies)
          return nil if candidates.empty?

          candidates.min_by { |entry| [ entry[:is_routing] ? 0 : 1, Geometry::Battlefield.distance_between_units(combatant, entry) ] }
        end

        def engaged?(combatant, enemy)
          return false unless enemy

          Geometry::Battlefield.distance_between_units(combatant, enemy) <= ENGAGE
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

        SETUP_RANGE_MV = 2.0

        # Plan assaults: front-arc only; one ally per defender side; else retarget, orbit flank, or wrap rear.
        # Pass 3: leftovers facing away from a nearby open flank/rear wheel toward it for next turn.
        def plan_melee_entries(movers, enemies)
          living = Pathing.active_units(enemies)
          ranked = movers.sort_by do |combatant|
            in_arc = enemies_in_front_arc(combatant, living)
            nearest = in_arc.min_by { |entry| Geometry::Battlefield.distance_between_units(combatant, entry) }
            dist = nearest ? Geometry::Battlefield.distance_between_units(combatant, nearest) : Float::INFINITY
            align = nearest ? front_alignment_to(combatant, nearest) : 999.0
            [ align, dist, combatant[:entity_id].to_s ]
          end

          claimed = Hash.new { |hash, key| hash[key] = {} }
          entries_by_id = {}

          # Pass 1: claim the natural geometric side while it is free.
          ranked.each do |combatant|
            choice = choose_natural_side(combatant, living, claimed)
            next unless choice

            enemy = choice[:nearest]
            side = choice[:contact_slot]
            claimed[enemy[:entity_id]][side] = combatant[:entity_id]
            entries_by_id[combatant[:entity_id]] = build_entry(combatant, enemy, side, :direct)
          end

          # Pass 2: leftovers retarget, else orbit a free flank, else wrap a free rear.
          ranked.each do |combatant|
            next if entries_by_id.key?(combatant[:entity_id])

            choice = choose_fallback_target(combatant, living, claimed)
            next unless choice

            enemy = choice[:nearest]
            side = choice[:contact_slot]
            claimed[enemy[:entity_id]][side] = combatant[:entity_id]
            entries_by_id[combatant[:entity_id]] = build_entry(combatant, enemy, side, choice[:approach_mode])
          end

          # Pass 3: no in-arc assault — if an open flank/rear is within MV*2, set up to strike it next turn.
          ranked.each do |combatant|
            next if entries_by_id.key?(combatant[:entity_id])

            choice = choose_setup_flank_or_rear(combatant, living, claimed)
            next unless choice

            enemy = choice[:nearest]
            side = choice[:contact_slot]
            claimed[enemy[:entity_id]][side] = combatant[:entity_id]
            entries_by_id[combatant[:entity_id]] = build_entry(combatant, enemy, side, choice[:approach_mode])
          end

          ranked.filter_map { |combatant| entries_by_id[combatant[:entity_id]] }
        end

        def build_entry(combatant, enemy, side, approach_mode)
          {
            combatant: combatant,
            nearest: enemy,
            distance: Geometry::Battlefield.distance_between_units(combatant, enemy),
            vector: Geometry::Battlefield.classify_attack_vector(combatant, enemy),
            contact_slot: side,
            approach_mode: approach_mode
          }
        end

        def choose_natural_side(combatant, enemies, claimed)
          candidates = enemies_in_front_arc(combatant, enemies).sort_by do |entry|
            [
              entry[:is_routing] ? 0 : 1,
              Geometry::Battlefield.distance_between_units(combatant, entry),
              entry[:entity_id].to_s
            ]
          end
          candidates.each do |enemy|
            side = Geometry::Battlefield.classify_attack_vector(combatant, enemy)
            next if claimed[enemy[:entity_id]].key?(side)

            return { nearest: enemy, contact_slot: side, approach_mode: :direct }
          end
          nil
        end

        # Other in-arc enemy with matching free side, else orbit free flank, else wrap free rear.
        def choose_fallback_target(combatant, enemies, claimed)
          candidates = enemies_in_front_arc(combatant, enemies).sort_by do |entry|
            [
              entry[:is_routing] ? 0 : 1,
              Geometry::Battlefield.distance_between_units(combatant, entry),
              entry[:entity_id].to_s
            ]
          end
          return nil if candidates.empty?

          candidates.each do |enemy|
            %w[front flank rear].each do |side|
              next if claimed[enemy[:entity_id]].key?(side)
              # Only claim a side that matches geometry on another (or same) in-arc foe.
              geo = Geometry::Battlefield.classify_attack_vector(combatant, enemy)
              next unless side == geo

              return { nearest: enemy, contact_slot: side, approach_mode: :direct }
            end
          end

          primary = candidates.first
          claimed_sides = claimed[primary[:entity_id]]
          unless claimed_sides.key?("flank")
            return { nearest: primary, contact_slot: "flank", approach_mode: :orbit_flank }
          end
          return nil if claimed_sides.key?("rear")

          { nearest: primary, contact_slot: "rear", approach_mode: :wrap_rear }
        end

        # Nearby open flank/rear outside the front arc: claim and wheel/approach for next turn.
        def choose_setup_flank_or_rear(combatant, enemies, claimed)
          return nil if engaged_with_any?(combatant, enemies)

          range = combatant[:movement].to_f * SETUP_RANGE_MV
          return nil if range <= 0.05

          candidates = Pathing.active_units(enemies).select do |enemy|
            Geometry::Battlefield.distance_between_units(combatant, enemy) <= range
          end
          return nil if candidates.empty?

          # Prefer foes already on our geometric flank/rear — less travel to set up.
          ordered = candidates.sort_by do |enemy|
            geo = Geometry::Battlefield.classify_attack_vector(combatant, enemy)
            geo_rank = %w[flank rear].include?(geo) ? 0 : 1
            [
              geo_rank,
              enemy[:is_routing] ? 0 : 1,
              Geometry::Battlefield.distance_between_units(combatant, enemy),
              enemy[:entity_id].to_s
            ]
          end

          ordered.each do |enemy|
            claimed_sides = claimed[enemy[:entity_id]]
            unless claimed_sides.key?("flank")
              return { nearest: enemy, contact_slot: "flank", approach_mode: :orbit_flank }
            end
            next if claimed_sides.key?("rear")

            return { nearest: enemy, contact_slot: "rear", approach_mode: :wrap_rear }
          end
          nil
        end

        def engaged_with_any?(combatant, enemies)
          Pathing.active_units(enemies).any? { |enemy| engaged?(combatant, enemy) }
        end

        # Pick a free side on an in-arc enemy, else orbit flank, else wrap rear.
        def choose_assault_target(combatant, enemies, claimed)
          choose_natural_side(combatant, enemies, claimed) || choose_fallback_target(combatant, enemies, claimed)
        end

        def orbit_mode?(approach_mode)
          approach_mode == :orbit_flank || approach_mode == :wrap_rear
        end

        # Kept for tests / callers that still group by target; prefer plan_melee_entries.
        def assign_contact_slots!(entries)
          entries.group_by { |entry| entry[:nearest][:entity_id] }.each_value do |group|
            ordered = group.sort_by do |entry|
              [
                front_alignment(entry),
                entry[:distance],
                entry[:combatant][:entity_id].to_s
              ]
            end
            ordered.each_with_index do |entry, index|
              geo = entry[:vector]
              entry[:contact_slot] ||=
                if index.zero?
                  "front"
                elsif geo == "rear"
                  "rear"
                else
                  "flank"
                end
              entry[:approach_mode] ||= :direct
            end
          end
          entries
        end

        def front_alignment(entry)
          front_alignment_to(entry[:combatant], entry[:nearest])
        end

        def front_alignment_to(combatant, enemy)
          Geometry::Battlefield.angle_between(enemy[:facing], enemy, combatant).to_f
        end

        def contact_wave?(entry)
          return false if orbit_mode?(entry[:approach_mode])
          return false if entry[:contact_slot] == "rear" || entry[:contact_slot] == "flank"
          return false if entry[:vector] == "flank" || entry[:vector] == "rear"
          return true if entry[:distance] <= ENGAGE + entry[:combatant][:movement].to_f * 0.35
          return true if entry[:contact_slot] == "front"

          false
        end

        def corner_contact_reachable?(origin, defender, budget)
          return false unless defender
          return true if engaged?(origin, defender)

          plan = Pathing.plan_approach(
            origin: origin,
            goal_point: defender,
            budget: budget.to_f,
            obstacles: [ defender ],
            contact_id: defender[:entity_id],
            goal_unit: defender,
            bypass: false
          )
          pose = plan[:pose]
          return false unless pose

          landed = origin.merge(x: pose[:x], y: pose[:y], facing: pose[:facing])
          Geometry::Battlefield.distance_between_units(landed, defender) <= ENGAGE
        end

        def build_approach_intent(combatant:, nearest:, obstacles:, contact_slot: nil, allow_ally_bypass: false, approach_mode: :direct)
          return nil unless nearest
          return nil if engaged?(combatant, nearest)
          return nil unless Geometry::Battlefield.in_front_arc?(combatant, nearest, combatant[:facing]) || orbit_mode?(approach_mode)

          budget = combatant[:movement].to_f
          goal_point = approach_goal_point(combatant, nearest, contact_slot: contact_slot, approach_mode: approach_mode)
          plan = Pathing.plan_approach(
            origin: combatant,
            goal_point: goal_point,
            budget: budget,
            obstacles: obstacles,
            contact_id: nearest[:entity_id],
            goal_unit: nearest,
            allow_ally_bypass: allow_ally_bypass || orbit_mode?(approach_mode),
            approach_mode: approach_mode
          )
          destination = plan[:pose]
          facing_changed = destination && Geometry::Battlefield.shortest_facing_delta(combatant[:facing], destination[:facing]).abs > 0.05
          traveled = destination ? Geometry::Battlefield.distance_between(combatant, destination) : 0.0
          meaningful_move = destination && (facing_changed || traveled > 0.05)

          if !meaningful_move
            return nil unless plan[:blocked_by_ally] && plan[:blocker]

            return {
              kind: "approach",
              combatant: combatant,
              nearest: nearest,
              plan: plan,
              budget: budget,
              destination: nil,
              wait: true,
              contact_slot: contact_slot,
              approach_mode: approach_mode
            }
          end

          {
            kind: "approach",
            combatant: combatant,
            nearest: nearest,
            plan: plan,
            budget: budget,
            destination: destination,
            wait: false,
            contact_slot: contact_slot,
            approach_mode: approach_mode
          }
        end

        # Direct assaults aim at the enemy. Orbit/wrap modes use flank or rear waypoints.
        def approach_goal_point(origin, defender, contact_slot:, approach_mode:)
          slot =
            case approach_mode
            when :orbit_flank then "flank"
            when :wrap_rear then "rear"
            else contact_slot.to_s
            end
          return defender unless orbit_mode?(approach_mode) && %w[flank rear].include?(slot)

          points = Pathing.contact_slot_points(origin, defender, slot)
          return points.min_by { |point| Geometry::Battlefield.distance_between(origin, point) } if points.any?

          defender
        end

        # Orbit/wrap modes bias off the defender face toward the assigned slot waypoint.
        def slot_approach_point(origin, defender, slot, approach_mode: :direct)
          return nil unless orbit_mode?(approach_mode)
          return nil if slot.nil? || slot.to_s == "front"

          point = approach_goal_point(origin, defender, contact_slot: slot, approach_mode: approach_mode)
          point == defender ? nil : point
        end
      end
    end
  end
end
