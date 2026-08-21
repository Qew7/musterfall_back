module Sim
  module Battle
    module Phases
      module Movement
        ADVANCING = Decisions::Movement::ADVANCING
        CONTACT = Pathing::CONTACT
        CONTACT_SNAP = Pathing::CONTACT_SNAP
        ENGAGE = Pathing::ENGAGE
        SLOT_RANK = Decisions::Movement::SLOT_RANK

        module_function

        def play(acting_side:, target_side:, round_number: 1, terrain: [], **)
          phase = AttackResolution.create_phase("movement", "Фаза движения")
          mobile = Decisions::Movement.melee_movers(acting_side[:combatants])
          physical_movers = mobile.select { |entry| entry[:movement].to_f > 0.05 }
          seekers = Decisions::Reposition.seekers(
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            terrain: terrain
          ).select { |entry| entry[:movement].to_f > 0.05 }

          moved = 0
          mobile.each do |combatant|
            target_row = Decisions::Movement.row_advance_target(combatant, acting_side[:combatants])
            next unless target_row

            # Row is a formation label only — keep battlefield pose so units never teleport backward.
            from = position_of(combatant)
            before = State.snapshot_combatant(combatant)
            combatant[:row] = target_row
            moved += 1
            after = State.snapshot_combatant(combatant)
            push_move!(
              phase,
              acting_side,
              target_side,
              combatant,
              before,
              after,
              from,
              "#{combatant[:name]} выдвигается в ряд #{target_row}.",
              maneuver: {
                kind: "row_advance",
                target_row: target_row,
                desired: { x: combatant[:x], y: combatant[:y], facing: combatant[:facing] },
                truncated_by_collision: false,
                avoided: false
              }
            )
          end

          # Rule planners own wave order (flyers, then ground contact per target, then flanks).
          Decisions::Movement.plan_melee_waves(physical_movers, target_side[:combatants], terrain: terrain).each do |wave|
            moved += run_melee_wave!(
              phase: phase,
              acting_side: acting_side,
              target_side: target_side,
              entries: wave[:entries],
              allow_ally_bypass: wave[:allow_ally_bypass],
              terrain: terrain
            )
          end

          melee_ids = physical_movers.map { |entry| entry[:entity_id] }.to_set
          seeker_units = seekers.reject { |entry| melee_ids.include?(entry[:entity_id]) }
          seeker_ids = seeker_units.map { |entry| entry[:entity_id] }.to_set
          # After melee moved, every non-seeker is a hard obstacle (including allies who just advanced).
          reposition_obstacles = movement_obstacles(acting_side, target_side, seeker_ids, terrain)
          reposition_intents = []

          seeker_units.sort_by { |entry| -entry[:initiative].to_i }.each do |combatant|
            intent = Decisions::Reposition.build_intent(
              combatant: combatant,
              acting_side: acting_side,
              target_side: target_side,
              obstacles: reposition_obstacles,
              round_number: round_number,
              terrain: terrain
            )
            next unless intent

            packed = intent.merge(
              from: position_of(combatant),
              before: State.snapshot_combatant(combatant),
              origin_pose: combatant.dup
            )
            resolve_destination_conflicts!([ packed ], reposition_obstacles)
            apply_intents!([ packed ])
            unless packed[:wait]
              # Subsequent seekers treat this landing as occupied.
              reposition_obstacles = reposition_obstacles.reject { |entry| entry[:entity_id] == combatant[:entity_id] }
              if packed[:destination]
                reposition_obstacles << combatant.merge(
                  x: packed[:destination][:x],
                  y: packed[:destination][:y],
                  facing: packed[:destination][:facing]
                )
              end
            end
            reposition_intents << packed
          end

          moved += commit_intents!(phase, acting_side, target_side, reposition_intents)
          apply_terrain_hazards!(phase, acting_side, target_side, terrain)
          Rules.for(:movement).after_play!(
            phase: phase,
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            terrain: terrain
          )

          AttackResolution.add_event(phase, "Строй удерживает позиции.") if moved.zero?
          phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          phase
        end

        def apply_terrain_hazards!(phase, acting_side, target_side, terrain)
          moved_ids = phase[:actions].filter_map do |action|
            next unless action[:type] == "movement"
            next unless Geometry::Battlefield.distance_between(action[:from], action[:to]) > 0.05

            action[:actor_id]
          end.uniq
          acting_side[:combatants].each do |combatant|
            next unless moved_ids.include?(combatant[:entity_id])

            feature = Array(terrain).find do |entry|
              entry[:entry_damage].to_i.positive? &&
                Geometry::Battlefield.unit_midpoint_in_feature?(combatant, entry)
            end
            next unless feature

            damage = [ feature[:entry_damage].to_i, combatant[:current_health].to_i ].min
            combatant[:current_health] -= damage
            State.sync_combatant_footprint!(combatant)
            summary = "#{combatant[:name]} получает #{damage} урона от опасной местности."
            AttackResolution.add_event(phase, summary)
            phase[:actions] << {
              type: "terrain_damage",
              actor_id: feature[:id],
              target_id: combatant[:entity_id],
              damage: damage,
              summary: summary,
              details: [ "terrain=#{feature[:id]} type=#{feature[:type]}", "damage=#{damage}" ],
              trace: Trace.build(rule_keys: [ "terrain" ], trigger: "movement_end", result: "damage", target_ids: [ combatant[:entity_id] ]),
              snapshot: State.snapshot_battlefield([ acting_side, target_side ])
            }
          end
        end

        def run_melee_wave!(phase:, acting_side:, target_side:, entries:, allow_ally_bypass:, terrain: [])
          return 0 if entries.empty?

          mover_ids = entries.map { |entry| entry[:combatant][:entity_id] }.to_set
          obstacles = movement_obstacles(acting_side, target_side, mover_ids, terrain)
          intents = []

          entries.each do |entry|
            intent = Decisions::Movement.build_approach_intent(
              combatant: entry[:combatant],
              nearest: entry[:nearest],
              obstacles: obstacles,
              enemies: target_side[:combatants],
              contact_slot: entry[:contact_slot],
              allow_ally_bypass: allow_ally_bypass,
              approach_mode: entry[:approach_mode] || :direct,
              terrain: terrain,
              chargeable: entry.fetch(:chargeable, true)
            )
            next unless intent

            intents << intent.merge(
              from: position_of(entry[:combatant]),
              before: State.snapshot_combatant(entry[:combatant]),
              origin_pose: entry[:combatant].dup,
              contact_slot: entry[:contact_slot],
              approach_mode: entry[:approach_mode] || :direct
            )
          end

          # Co-movers that never move still occupy their start — treat as hard blockers
          # so others cannot land inside them (idle heroes, wait intents, etc.).
          occupied = obstacles + wave_stayers(entries, intents).map { |entry| freeze_obstacle(entry) }
          resolve_destination_conflicts!(intents, occupied)
          # Landing conflict can turn a co-mover into a waiter after everyone already
          # planned through their start. Re-path those sweeps; thread wrap already exists.
          reroute_around_stayers!(
            intents,
            obstacles,
            stayers: wave_stayers(entries, intents),
            enemies: target_side[:combatants],
            terrain: terrain
          )
          occupied = obstacles + wave_stayers(entries, intents).map { |entry| freeze_obstacle(entry) }
          resolve_destination_conflicts!(intents, occupied)
          apply_free_aligns!(intents, occupied)
          apply_intents!(intents)
          commit_intents!(phase, acting_side, target_side, intents)
        end

        def wave_stayers(entries, intents)
          entries.map { |entry| entry[:combatant] }.select do |unit|
            intent = intents.find { |row| row[:combatant][:entity_id] == unit[:entity_id] }
            intent.nil? || intent[:wait] || intent[:destination].nil?
          end
        end

        def reroute_around_stayers!(intents, obstacles, stayers:, enemies:, terrain:)
          return if stayers.empty?

          world = obstacles + stayers.map { |entry| freeze_obstacle(entry) }
          space = Pathing::Obstacles.coerce(world)

          intents.each do |intent|
            next if intent[:wait] || intent[:destination].nil?

            unit = intent[:combatant]
            pose = destination_pose(intent)
            contact_id = charge_contact_id_for(intent)
            next if space.except(unit[:entity_id]).translation_clear?(unit, unit, pose, contact_id: contact_id)

            fresh = Decisions::Movement.build_approach_intent(
              combatant: unit,
              nearest: intent[:nearest],
              obstacles: world,
              enemies: enemies,
              contact_slot: intent[:contact_slot],
              allow_ally_bypass: false,
              approach_mode: intent[:approach_mode] || :direct,
              terrain: terrain,
              chargeable: !contact_id.nil?
            )
            if fresh.nil? || fresh[:wait] || fresh[:destination].nil?
              intent[:wait] = true
              intent[:destination] = nil
              intent[:plan] = (intent[:plan] || {}).merge(
                blocked_by_ally: true,
                blocker: stayers.first.slice(:entity_id, :name)
              )
            else
              intent[:plan] = fresh[:plan]
              intent[:destination] = fresh[:destination]
              intent[:budget] = fresh[:budget]
              intent[:march_meta] = fresh[:march_meta]
              intent[:charge_contact_id] = fresh[:charge_contact_id] if fresh.key?(:charge_contact_id)
            end
          end
        end

        # After paid approach reaches ENGAGE, freely wheel to press fronts (no slide, no MV cost).
        def apply_free_aligns!(intents, hard_obstacles)
          intents.each do |intent|
            next if intent[:wait] || intent[:destination].nil?

            nearest = intent[:nearest]
            next unless nearest

            pose = destination_pose(intent)
            next unless Decisions::Movement.engaged?(pose, nearest)

            # Include same-wave allies (excluded from hard_obstacles as co-movers) so idle friends
            # still steer free-align away from their half.
            ally_blockers = intents.filter_map do |other|
              next if other[:combatant][:entity_id] == intent[:combatant][:entity_id]

              unit = other[:wait] || other[:destination].nil? ? other[:combatant] : destination_pose(other)
              freeze_obstacle(unit)
            end
            align_obstacles = hard_obstacles + ally_blockers

            aligned = Geometry::Battlefield.align_fronts_pose(pose, nearest, obstacles: align_obstacles)
            next unless meaningful_destination?(pose, aligned)
            soft_id = charge_contact_id_for(intent) || nearest[:entity_id]
            next if destination_blocked?(aligned, [], align_obstacles, contact_id: soft_id)

            intent[:paid_destination] = intent[:destination].dup
            intent[:destination] = Geometry::Battlefield.footprint_destination(
              Geometry::Battlefield.merge_footprint(aligned, intent[:destination]).merge(
                x: aligned[:x],
                y: aligned[:y],
                facing: aligned[:facing]
              )
            )
            intent[:free_align] = true
          end
        end

        def apply_intents!(intents)
          intents.each do |intent|
            next if intent[:wait]

            destination = intent[:destination]
            combatant = intent[:combatant]
            Geometry::Battlefield.apply_footprint!(combatant, destination)
            combatant[:x] = destination[:x]
            combatant[:y] = destination[:y]
            combatant[:facing] = destination[:facing]
          end
        end

        # Simultaneous melee: each mover vacates its start only while evaluating its landing.
        # Starts of units that wait (or never intended to move) stay occupied, so nobody
        # lands inside a stationary ally. Charge targets are soft — contact band is allowed.
        def resolve_destination_conflicts!(intents, static_obstacles)
          occupied = static_obstacles.map { |entry| freeze_obstacle(entry) }
          intents.each do |intent|
            occupied << freeze_obstacle(intent[:combatant])
          end

          ranked = intents.reject { |intent| intent[:wait] || intent[:destination].nil? }
          ranked.sort_by! do |intent|
            pose = destination_pose(intent)
            nearest = intent[:nearest]
            dist = if nearest
              Geometry::Battlefield.distance_between_units(pose, nearest)
            else
              0.0
            end
            slot = SLOT_RANK.fetch(intent[:contact_slot], 1)
            [ slot, dist, -intent[:combatant][:initiative].to_i, intent[:combatant][:entity_id].to_s ]
          end

          ranked.each do |intent|
            combatant = intent[:combatant]
            occupied.reject! { |entry| entry[:entity_id] == combatant[:entity_id] }
            contact_id = charge_contact_id_for(intent)

            pose = destination_pose(intent)
            if destination_blocked?(pose, [], occupied, contact_id: contact_id)
              pose = shorten_destination(combatant, pose, [], occupied, contact_id: contact_id)
            end

            if pose.nil? || !meaningful_destination?(combatant, pose)
              intent[:wait] = true
              intent[:destination] = nil
              intent[:plan] = (intent[:plan] || {}).merge(
                blocked_by_ally: true,
                blocker: intent.dig(:plan, :blocker) || { name: "союзник", entity_id: nil }
              )
              occupied << freeze_obstacle(combatant)
            else
              intent[:destination] = Geometry::Battlefield.footprint_destination(pose)
              occupied << pose
            end
          end
        end

        def destination_pose(intent)
          Geometry::Battlefield.merge_footprint(
            intent[:combatant],
            intent[:destination]
          )
        end

        # Flyer setup sets charge_contact_id: nil so landing stays clear of everyone.
        # Charge / ground intents omit the key and soft-contact the nearest enemy.
        def charge_contact_id_for(intent)
          return intent[:charge_contact_id] if intent.key?(:charge_contact_id)

          intent.dig(:nearest, :entity_id)
        end

        def destination_blocked?(pose, static_obstacles, accepted, contact_id: nil)
          static_obstacles.any? { |obs| footprints_conflict?(pose, obs, contact_id: contact_id) } ||
            accepted.any? { |other| footprints_conflict?(pose, other, contact_id: contact_id) }
        end

        def meaningful_destination?(origin, pose)
          Geometry::Battlefield.distance_between(origin, pose) > 0.05 ||
            Geometry::Battlefield.shortest_facing_delta(origin[:facing], pose[:facing]).abs > 0.05
        end

        # Pull the destination back toward the origin until clear of accepted/static poses.
        def shorten_destination(origin, desired, static_obstacles, accepted, contact_id: nil)
          best = nil
          from_facing = origin[:facing].to_f
          facing_delta = Geometry::Battlefield.shortest_facing_delta(from_facing, desired[:facing])
          12.times do |index|
            t = 1.0 - ((index + 1) / 12.0)
            pose = origin.merge(
              x: origin[:x].to_f + ((desired[:x].to_f - origin[:x].to_f) * t),
              y: origin[:y].to_f + ((desired[:y].to_f - origin[:y].to_f) * t),
              facing: Geometry::Battlefield.normalize_facing(from_facing + (facing_delta * t))
            )
            pose = Geometry::Battlefield.merge_footprint(pose, desired)
            next if destination_blocked?(pose, static_obstacles, accepted, contact_id: contact_id)

            best = pose
            break
          end
          best
        end

        # Soft-contact: the charge target may sit in the contact band (padding..CONTACT).
        # Hard-block only true OBB overlap against that target; everyone else uses CONTACT.
        def footprints_conflict?(left, right, contact_id: nil)
          return false if left[:entity_id] == right[:entity_id]
          return false if right[:current_health].to_i <= 0

          if contact_id && right[:entity_id] == contact_id
            return Geometry::Battlefield.rectangles_overlap?(left, right)
          end

          Geometry::Battlefield.distance_between_units(left, right) < CONTACT
        end

        def commit_intents!(phase, acting_side, target_side, intents)
          moved = 0
          intents.each do |intent|
            combatant = intent[:combatant]
            nearest = intent[:nearest]
            plan = intent[:plan] || {}
            budget = intent[:budget]
            from = intent[:from]
            before = intent[:before]
            origin_pose = intent[:origin_pose]
            moved += 1

            if intent[:wait] || intent[:destination].nil?
              after = before
              blocker_name = plan.dig(:blocker, :name) || "союзника"
              push_move!(
                phase,
                acting_side,
                target_side,
                combatant,
                before,
                after,
                from,
                "#{combatant[:name]} ждёт прохода у #{blocker_name}.",
                wheel: nil,
                maneuver: approach_maneuver(plan, nearest, budget, wheel: nil, turn: nil, advance_spent: 0.0, march_spent: 0.0, desired: combatant, kind_override: "blocked_by_ally"),
                origin_pose: origin_pose
              )
              next
            end

            destination = intent[:destination]
            after = State.snapshot_combatant(combatant)
            # MV accounting uses the paid landing; free align after contact costs no movement.
            paid = intent[:paid_destination] || destination
            planned_wheel = plan[:wheel]
            planned_turn = plan[:turn]
            applied_wheel = wheel_for_applied_move(origin_pose, paid, planned_wheel)
            applied_turn = turn_for_applied_move(origin_pose, paid, planned_turn)
            pivot = applied_turn || applied_wheel
            travel = Geometry::Battlefield.distance_between(
              pivot ? { x: pivot[:x], y: pivot[:y] } : origin_pose,
              paid
            )
            wheel_cost = applied_wheel ? applied_wheel[:cost].to_f : 0.0
            turn_cost = applied_turn ? applied_turn[:cost].to_f : 0.0
            if plan[:maneuver] == :march
              rate = (plan[:march_multiplier] || Geometry::Battlefield::CONFIG[:march_multiplier]).to_f
              march_spent = travel / rate
              advance_spent = 0.0
            else
              march_spent = 0.0
              advance_spent = travel
              if budget && (wheel_cost + turn_cost + advance_spent) > budget.to_f
                advance_spent = [ budget.to_f - wheel_cost - turn_cost, 0.0 ].max
              end
            end
            desired = plan[:desired] || paid
            summary =
              if intent[:kind] == "reposition"
                reposition_player_summary(combatant, nearest, plan)
              else
                approach_player_summary(combatant, nearest, plan)
              end
            maneuver = approach_maneuver(
              plan,
              nearest,
              budget,
              wheel: applied_wheel,
              turn: applied_turn,
              advance_spent: advance_spent,
              march_spent: march_spent,
              desired: desired,
              kind_override: intent[:kind] == "reposition" ? "reposition" : nil
            )
            maneuver = maneuver.merge(contact_slot: intent[:contact_slot]) if intent[:contact_slot]
            maneuver = maneuver.merge(free_align: true) if intent[:free_align]
            if intent[:approach_mode]
              maneuver = maneuver.merge(approach_mode: intent[:approach_mode].to_s)
            end
            maneuver = maneuver.merge(intent[:march_meta]) if intent[:march_meta].present?
            push_move!(
              phase,
              acting_side,
              target_side,
              combatant,
              before,
              after,
              from,
              summary,
              wheel: applied_wheel,
              turn: applied_turn,
              maneuver: maneuver,
              origin_pose: origin_pose
            )
          end
          moved
        end

        # Enemies and non-moving allies only — co-movers are resolved together, not sequenced.
        # Impassable terrain is merged into the same obstacle list for Pathing bypass.
        def movement_obstacles(acting_side, target_side, mover_ids, terrain = [])
          allies = Pathing.active_units(acting_side[:combatants]).reject { |entry| mover_ids.include?(entry[:entity_id]) }
          enemies = Pathing.active_units(target_side[:combatants])
          Pathing::Obstacles.merge((allies + enemies).map { |entry| freeze_obstacle(entry) }, terrain)
        end

        def freeze_obstacle(entry)
          entry.merge(
            x: entry[:x].to_f,
            y: entry[:y].to_f,
            facing: entry[:facing].to_f,
            base_width: entry[:base_width].to_f,
            base_depth: entry[:base_depth].to_f,
            current_health: entry[:current_health].to_i
          )
        end

        def nearest_enemy(...)
          Decisions::Movement.nearest_enemy(...)
        end

        # Player-facing: short and truthful. Wheel MV / pathing flags belong in details.
        def approach_player_summary(combatant, nearest, plan)
          note = approach_player_note(plan, nearest)
          if plan[:leap] && plan[:charge]
            "#{combatant[:name]} пикирует на #{nearest[:name]}#{note}."
          elsif plan[:leap]
            "#{combatant[:name]} перелетает к #{nearest[:name]}#{note}."
          elsif plan[:turn] && plan[:turn][:cost].to_f > 0.05
            flank = plan[:turn][:delta].to_f.positive? ? "правый" : "левый"
            "#{combatant[:name]} разворачивается на #{flank} фланг и сближается с #{nearest[:name]}#{note}."
          elsif plan[:maneuver] == :march
            "#{combatant[:name]} марширует к #{nearest[:name]}#{note}."
          else
            "#{combatant[:name]} сближается с #{nearest[:name]}#{note}."
          end
        end

        def reposition_player_summary(combatant, nearest, plan)
          note = approach_player_note(plan, nearest)
          if nearest
            "#{combatant[:name]} занимает позицию против #{nearest[:name]}#{note}."
          else
            "#{combatant[:name]} меняет позицию#{note}."
          end
        end

        def approach_player_note(plan, nearest)
          blocker = plan[:blocker]
          return "" unless blocker

          blocker_label = Pathing.terrain_obstacle?(blocker) ? "местность (#{blocker[:name]})" : blocker[:name]

          if plan[:blocked_by_ally]
            ", путь закрыт союзником #{blocker[:name]}"
          elsif blocker_is_target?(plan, nearest)
            # Soft-stop / align on the charge target is not "обходит".
            plan[:truncated] ? ", выходит на контакт" : ""
          elsif plan[:avoided]
            ", обходит #{blocker_label}"
          elsif plan[:truncated]
            ", путь преграждён #{blocker_label}"
          else
            ""
          end
        end

        def blocker_is_target?(plan, nearest)
          return false unless plan[:blocker] && nearest

          plan[:blocker][:entity_id] == nearest[:entity_id]
        end

        def maneuver_log_kind(plan, contact_blocker, wheel, turn, advance_spent, march_spent)
          return plan[:kind] if plan[:kind]
          return "blocked_by_ally" if plan[:blocked_by_ally]
          return "bypass" if plan[:avoided] && !contact_blocker
          return "contact_align" if contact_blocker && plan[:truncated]

          maneuver_kind(plan, wheel, turn, advance_spent, march_spent)
        end

        def approach_maneuver(plan, nearest, budget, wheel:, turn:, advance_spent:, march_spent:, desired:, kind_override: nil)
          contact_blocker = blocker_is_target?(plan, nearest)
          kind = kind_override || maneuver_log_kind(plan, contact_blocker, wheel, turn, advance_spent, march_spent)

          {
            kind: kind,
            target_id: nearest && nearest[:entity_id],
            target_name: nearest && nearest[:name],
            heading: plan[:heading],
            desired_facing: plan[:heading],
            mv_budget: budget,
            mv_spent_wheel: wheel ? wheel[:cost].to_f : 0.0,
            mv_spent_turn: turn ? turn[:cost].to_f : 0.0,
            mv_spent_advance: advance_spent.to_f,
            mv_spent_march: march_spent.to_f,
            desired: { x: desired[:x], y: desired[:y], facing: desired[:facing] },
            truncated_by_collision: !!plan[:truncated],
            avoided: !!plan[:avoided] && !contact_blocker,
            pathing_avoided: !!plan[:avoided],
            blocked_by_ally: !!plan[:blocked_by_ally],
            blocker_id: plan.dig(:blocker, :entity_id),
            blocker_name: plan.dig(:blocker, :name),
            blocker_is_target: contact_blocker,
            wheel_direction: wheel_direction(wheel),
            turn_direction: turn_direction(turn),
            steps: Array(plan[:steps])
          }
        end

        def wheel_for_applied_move(origin, destination, planned_wheel)
          return nil unless planned_wheel && planned_wheel[:cost].to_f > 0.05

          applied_delta = Geometry::Battlefield.shortest_facing_delta(origin[:facing], destination[:facing])
          return nil if applied_delta.abs < 0.05
          return planned_wheel if Geometry::Battlefield.shortest_facing_delta(destination[:facing], planned_wheel[:facing]).abs < 0.05

          {
            x: destination[:x],
            y: destination[:y],
            facing: destination[:facing],
            delta: applied_delta,
            cost: Geometry::Battlefield.wheel_cost(origin, origin[:facing], destination[:facing])
          }
        end

        def turn_for_applied_move(origin, destination, planned_turn)
          return nil unless planned_turn && planned_turn[:cost].to_f > 0.05

          applied_delta = Geometry::Battlefield.shortest_facing_delta(origin[:facing], destination[:facing])
          return nil unless Geometry::Battlefield.turn_delta?(applied_delta)

          planned_turn
        end

        def maneuver_kind(plan, wheel, turn, advance_spent, march_spent)
          return "turn" if turn && turn[:cost].to_f > 0.05
          return "march" if plan[:maneuver] == :march || march_spent.to_f > 0.05
          return plan[:maneuver].to_s if plan[:maneuver]
          return "wheel" if wheel && wheel[:cost].to_f > 0.05
          return "advance" if advance_spent.to_f > 0.05

          "hold"
        end

        def wheel_direction(wheel)
          delta = wheel && wheel[:delta].to_f
          return nil if delta.nil? || delta.abs < 0.05

          delta.positive? ? "right" : "left"
        end

        def turn_direction(turn)
          delta = turn && turn[:delta].to_f
          return nil if delta.nil? || delta.abs < 0.05

          delta.positive? ? "right" : "left"
        end

        def push_move!(phase, acting_side, target_side, combatant, before, after, from, summary, wheel: nil, turn: nil, maneuver: nil, origin_pose: nil)
          to = position_of(combatant)
          AttackResolution.add_event(phase, summary)
          details = build_movement_details(
            combatant: combatant,
            before: before,
            after: after,
            from: from,
            to: to,
            wheel: wheel,
            turn: turn,
            maneuver: maneuver,
            origin_pose: origin_pose || combatant
          )

          phase[:actions] << {
            type: "movement",
            actor_id: combatant[:entity_id],
            actor_name: combatant[:name],
            actor_state_before: before,
            actor_state_after: after,
            summary: summary,
            details: details,
            from: from,
            to: to,
            wheel: wheel && wheel[:cost].to_f > 0.05 ? { x: wheel[:x], y: wheel[:y], facing: wheel[:facing], delta: wheel[:delta], cost: wheel[:cost], direction: wheel_direction(wheel) } : nil,
            turn: turn && turn[:cost].to_f > 0.05 ? { x: turn[:x], y: turn[:y], facing: turn[:facing], delta: turn[:delta], cost: turn[:cost], direction: turn_direction(turn) } : nil,
            maneuver: maneuver,
            trace: Trace.build(
              rule_keys: Trace.movement_rule_keys(combatant, maneuver),
              trigger: "movement_plan",
              result: maneuver && maneuver[:kind] || "hold",
              target_ids: [ maneuver && maneuver[:target_id] ]
            ),
            snapshot: State.snapshot_battlefield([ acting_side, target_side ])
          }
        end

        def build_movement_details(combatant:, before:, after:, from:, to:, wheel:, turn:, maneuver:, origin_pose:)
          facing_delta = Geometry::Battlefield.shortest_facing_delta(from[:facing], to[:facing])
          traveled = Geometry::Battlefield.distance_between(from, to)
          lines = [
            "actor=#{combatant[:entity_id]} #{combatant[:name]} side=#{combatant[:side_index]}",
            "from=(#{format_point(from[:x])}, #{format_point(from[:y])}) f#{format("%.1f", from[:facing].to_f)}° #{from[:row]}/#{from[:lane]}",
            "to=(#{format_point(to[:x])}, #{format_point(to[:y])}) f#{format("%.1f", to[:facing].to_f)}° #{to[:row]}/#{to[:lane]} Δxy=#{format("%.2f", traveled)} Δfacing=#{format("%+.1f", facing_delta)}°",
            "HP #{before[:current_health]}/#{before[:max_health]} → #{after[:current_health]}/#{after[:max_health]}, models #{before[:models_remaining]} → #{after[:models_remaining]}"
          ]

          if maneuver
            lines << "maneuver.kind=#{maneuver[:kind]} avoided=#{maneuver[:avoided]} pathing_avoided=#{maneuver[:pathing_avoided]} blocked_by_ally=#{maneuver[:blocked_by_ally]} truncated=#{maneuver[:truncated_by_collision]}"
            if maneuver[:contact_slot]
              lines << "contact_slot=#{maneuver[:contact_slot]}"
            end
            if maneuver[:free_align]
              lines << "free_align=true"
            end
            if maneuver[:approach_mode]
              lines << "approach_mode=#{maneuver[:approach_mode]}"
            end
            if maneuver[:target_id]
              lines << "target=#{maneuver[:target_name]}(#{maneuver[:target_id]}) heading=#{format("%.1f", maneuver[:heading].to_f)}° desired=(#{format_point(maneuver.dig(:desired, :x))}, #{format_point(maneuver.dig(:desired, :y))}) f#{format("%.0f", maneuver.dig(:desired, :facing).to_f)}°"
            end
            if maneuver[:blocker_id]
              lines << "blocker=#{maneuver[:blocker_name]}(#{maneuver[:blocker_id]}) blocker_is_target=#{maneuver[:blocker_is_target]}"
            end
            if maneuver[:mv_budget]
              lines << "MV budget=#{format("%.2f", maneuver[:mv_budget].to_f)} wheel=#{format("%.2f", maneuver[:mv_spent_wheel].to_f)} turn=#{format("%.2f", maneuver[:mv_spent_turn].to_f)} advance=#{format("%.2f", maneuver[:mv_spent_advance].to_f)} march=#{format("%.2f", maneuver[:mv_spent_march].to_f)} dir=#{maneuver[:wheel_direction] || maneuver[:turn_direction] || "-"}"
            end
            Array(maneuver[:steps]).each do |step|
              lines << "step kind=#{step[:kind]} cost=#{format("%.2f", step[:cost].to_f)}"
            end
            if maneuver[:march] == "active"
              lines << "march=active clearance=#{format("%.1f", maneuver[:march_clearance].to_f)} multiplier=#{format("%.1f", maneuver[:march_multiplier].to_f)}"
            elsif maneuver[:march] == "blocked"
              lines << "march=blocked clearance=#{format("%.1f", maneuver[:march_clearance].to_f)} blocker=#{maneuver[:march_blocker_name]}(#{maneuver[:march_blocker_id]}) dist=#{format("%.2f", maneuver[:march_blocker_dist].to_f)}"
            end
          end

          if wheel && wheel[:cost].to_f > 0.05
            lines << "wheel Δ=#{format("%+.1f", wheel[:delta].to_f)}° cost=#{format("%.2f", wheel[:cost].to_f)} pose=(#{format_point(wheel[:x])}, #{format_point(wheel[:y])}) f#{format("%.1f", wheel[:facing].to_f)}°"
          end
          if turn && turn[:cost].to_f > 0.05
            lines << "turn Δ=#{format("%+.1f", turn[:delta].to_f)}° cost=#{format("%.2f", turn[:cost].to_f)} facing=#{format("%.1f", turn[:facing].to_f)}°"
          end

          lines
        end

        def position_of(combatant)
          { x: combatant[:x], y: combatant[:y], facing: combatant[:facing], row: combatant[:row], lane: combatant[:lane] }
        end

        def format_point(value)
          format("%.1f", value.to_f)
        end
      end
    end
  end
end
