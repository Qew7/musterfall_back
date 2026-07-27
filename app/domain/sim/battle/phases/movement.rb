module Sim
  module Battle
    module Phases
      module Movement
        ADVANCING = Decisions::Movement::ADVANCING
        CONTACT = Pathing::CONTACT

        module_function

        def play(acting_side:, target_side:, round_number: 1, **)
          phase = AttackResolution.create_phase("movement", "Фаза движения")
          mobile = Decisions::Movement.melee_movers(acting_side[:combatants])
          physical_movers = mobile.select { |entry| entry[:movement].to_f > 0.05 }
          seekers = Decisions::Reposition.seekers(
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number
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

          # 1) Melee approaches resolve first (simultaneous among themselves, conflict-safe).
          # 2) Reposition runs on the post-melee board so seekers never claim a melee unit's landing spot.
          melee_ids = physical_movers.map { |entry| entry[:entity_id] }.to_set
          melee_obstacles = movement_obstacles(acting_side, target_side, melee_ids)
          melee_intents = []

          physical_movers.each do |combatant|
            nearest = Decisions::Movement.nearest_enemy(combatant, target_side[:combatants])
            intent = Decisions::Movement.build_approach_intent(
              combatant: combatant,
              nearest: nearest,
              obstacles: melee_obstacles
            )
            next unless intent

            melee_intents << intent.merge(
              from: position_of(combatant),
              before: State.snapshot_combatant(combatant),
              origin_pose: combatant.dup
            )
          end

          # Co-movers that never move still occupy their start — treat as hard blockers
          # so others cannot land inside them (idle heroes, wait intents, etc.).
          stayers = physical_movers.select do |entry|
            intent = melee_intents.find { |row| row[:combatant][:entity_id] == entry[:entity_id] }
            intent.nil? || intent[:wait] || intent[:destination].nil?
          end
          resolve_destination_conflicts!(
            melee_intents,
            melee_obstacles + stayers.map { |entry| freeze_obstacle(entry) }
          )
          apply_intents!(melee_intents)
          moved += commit_intents!(phase, acting_side, target_side, melee_intents)

          seeker_units = seekers.reject { |entry| melee_ids.include?(entry[:entity_id]) }
          seeker_ids = seeker_units.map { |entry| entry[:entity_id] }.to_set
          # After melee moved, every non-seeker is a hard obstacle (including allies who just advanced).
          reposition_obstacles = movement_obstacles(acting_side, target_side, seeker_ids)
          reposition_intents = []

          seeker_units.sort_by { |entry| -entry[:initiative].to_i }.each do |combatant|
            intent = Decisions::Reposition.build_intent(
              combatant: combatant,
              acting_side: acting_side,
              target_side: target_side,
              obstacles: reposition_obstacles,
              round_number: round_number
            )
            next unless intent

            packed = intent.merge(
              from: position_of(combatant),
              before: State.snapshot_combatant(combatant),
              origin_pose: combatant.dup
            )
            resolve_destination_conflicts!([packed], reposition_obstacles)
            apply_intents!([packed])
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

          AttackResolution.add_event(phase, "Строй удерживает позиции.") if moved.zero?
          phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          phase
        end

        def apply_intents!(intents)
          intents.each do |intent|
            next if intent[:wait]

            destination = intent[:destination]
            combatant = intent[:combatant]
            combatant[:x] = destination[:x]
            combatant[:y] = destination[:y]
            combatant[:facing] = destination[:facing]
          end
        end

        # Simultaneous melee: each mover vacates its start only while evaluating its landing.
        # Starts of units that wait (or never intended to move) stay occupied, so nobody
        # lands inside a stationary ally.
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
            [ dist, -intent[:combatant][:initiative].to_i, intent[:combatant][:entity_id].to_s ]
          end

          ranked.each do |intent|
            combatant = intent[:combatant]
            occupied.reject! { |entry| entry[:entity_id] == combatant[:entity_id] }

            pose = destination_pose(intent)
            if destination_blocked?(pose, [], occupied)
              pose = shorten_destination(combatant, pose, [], occupied)
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
              intent[:destination] = { x: pose[:x], y: pose[:y], facing: pose[:facing] }
              occupied << pose
            end
          end
        end

        def destination_pose(intent)
          intent[:combatant].merge(
            x: intent[:destination][:x],
            y: intent[:destination][:y],
            facing: intent[:destination][:facing]
          )
        end

        def destination_blocked?(pose, static_obstacles, accepted)
          static_obstacles.any? { |obs| footprints_conflict?(pose, obs) } ||
            accepted.any? { |other| footprints_conflict?(pose, other) }
        end

        def meaningful_destination?(origin, pose)
          Geometry::Battlefield.distance_between(origin, pose) > 0.05 ||
            Geometry::Battlefield.shortest_facing_delta(origin[:facing], pose[:facing]).abs > 0.05
        end

        # Pull the destination back toward the origin until clear of accepted/static poses.
        def shorten_destination(origin, desired, static_obstacles, accepted)
          best = nil
          12.times do |index|
            t = 1.0 - ((index + 1) / 12.0)
            pose = origin.merge(
              x: origin[:x].to_f + ((desired[:x].to_f - origin[:x].to_f) * t),
              y: origin[:y].to_f + ((desired[:y].to_f - origin[:y].to_f) * t),
              facing: desired[:facing]
            )
            next if destination_blocked?(pose, static_obstacles, accepted)

            best = pose
            break
          end
          best
        end

        def footprints_conflict?(left, right)
          return false if left[:entity_id] == right[:entity_id]
          return false if right[:current_health].to_i <= 0

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
                maneuver: approach_maneuver(plan, nearest, budget, wheel: nil, march_spent: 0.0, desired: combatant, kind_override: "blocked_by_ally"),
                origin_pose: origin_pose
              )
              next
            end

            destination = intent[:destination]
            after = State.snapshot_combatant(combatant)
            planned_wheel = plan[:wheel]
            applied_wheel = wheel_for_applied_move(origin_pose, destination, planned_wheel)
            march_spent = Geometry::Battlefield.distance_between(
              applied_wheel ? { x: applied_wheel[:x], y: applied_wheel[:y] } : origin_pose,
              destination
            )
            desired = plan[:desired] || destination
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
              march_spent: march_spent,
              desired: desired,
              kind_override: intent[:kind] == "reposition" ? "reposition" : nil
            )
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
              maneuver: maneuver,
              origin_pose: origin_pose
            )
          end
          moved
        end

        # Enemies and non-moving allies only — co-movers are resolved together, not sequenced.
        def movement_obstacles(acting_side, target_side, mover_ids)
          allies = Pathing.active_units(acting_side[:combatants]).reject { |entry| mover_ids.include?(entry[:entity_id]) }
          enemies = Pathing.active_units(target_side[:combatants])
          (allies + enemies).map { |entry| freeze_obstacle(entry) }
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
          "#{combatant[:name]} сближается с #{nearest[:name]}#{note}."
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

          if plan[:blocked_by_ally]
            ", путь закрыт союзником #{blocker[:name]}"
          elsif blocker_is_target?(plan, nearest)
            # Soft-stop / align on the charge target is not "обходит".
            plan[:truncated] ? ", выходит на контакт" : ""
          elsif plan[:avoided]
            ", обходит #{blocker[:name]}"
          elsif plan[:truncated]
            ", путь преграждён #{blocker[:name]}"
          else
            ""
          end
        end

        def blocker_is_target?(plan, nearest)
          return false unless plan[:blocker] && nearest

          plan[:blocker][:entity_id] == nearest[:entity_id]
        end

        def approach_maneuver(plan, nearest, budget, wheel:, march_spent:, desired:, kind_override: nil)
          contact_blocker = blocker_is_target?(plan, nearest)
          kind = kind_override || if plan[:blocked_by_ally]
            "blocked_by_ally"
          elsif plan[:avoided] && !contact_blocker
            "bypass"
          elsif contact_blocker && plan[:truncated]
            "contact_align"
          else
            maneuver_kind(wheel, march_spent)
          end

          {
            kind: kind,
            target_id: nearest && nearest[:entity_id],
            target_name: nearest && nearest[:name],
            heading: plan[:heading],
            desired_facing: plan[:heading],
            mv_budget: budget,
            mv_spent_wheel: wheel ? wheel[:cost].to_f : 0.0,
            mv_spent_march: march_spent.to_f,
            desired: { x: desired[:x], y: desired[:y], facing: desired[:facing] },
            truncated_by_collision: !!plan[:truncated],
            avoided: !!plan[:avoided] && !contact_blocker,
            pathing_avoided: !!plan[:avoided],
            blocked_by_ally: !!plan[:blocked_by_ally],
            blocker_id: plan.dig(:blocker, :entity_id),
            blocker_name: plan.dig(:blocker, :name),
            blocker_is_target: contact_blocker,
            wheel_direction: wheel_direction(wheel)
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

        def maneuver_kind(wheel, march_spent)
          wheeled = wheel && wheel[:cost].to_f > 0.05
          marched = march_spent.to_f > 0.05
          return "wheel_and_march" if wheeled && marched
          return "wheel" if wheeled
          return "march" if marched

          "hold"
        end

        def wheel_direction(wheel)
          delta = wheel && wheel[:delta].to_f
          return nil if delta.nil? || delta.abs < 0.05

          delta.positive? ? "right" : "left"
        end

        def push_move!(phase, acting_side, target_side, combatant, before, after, from, summary, wheel: nil, maneuver: nil, origin_pose: nil)
          to = position_of(combatant)
          AttackResolution.add_event(phase, summary)
          details = build_movement_details(
            combatant: combatant,
            before: before,
            after: after,
            from: from,
            to: to,
            wheel: wheel,
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
            maneuver: maneuver,
            snapshot: State.snapshot_battlefield([ acting_side, target_side ])
          }
        end

        def build_movement_details(combatant:, before:, after:, from:, to:, wheel:, maneuver:, origin_pose:)
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
            if maneuver[:target_id]
              lines << "target=#{maneuver[:target_name]}(#{maneuver[:target_id]}) heading=#{format("%.1f", maneuver[:heading].to_f)}° desired=(#{format_point(maneuver.dig(:desired, :x))}, #{format_point(maneuver.dig(:desired, :y))}) f#{format("%.0f", maneuver.dig(:desired, :facing).to_f)}°"
            end
            if maneuver[:blocker_id]
              lines << "blocker=#{maneuver[:blocker_name]}(#{maneuver[:blocker_id]}) blocker_is_target=#{maneuver[:blocker_is_target]}"
            end
            if maneuver[:mv_budget]
              lines << "MV budget=#{format("%.2f", maneuver[:mv_budget].to_f)} wheel=#{format("%.2f", maneuver[:mv_spent_wheel].to_f)} march=#{format("%.2f", maneuver[:mv_spent_march].to_f)} dir=#{maneuver[:wheel_direction] || "-"}"
            end
          end

          if wheel && wheel[:cost].to_f > 0.05
            lines << "wheel Δ=#{format("%+.1f", wheel[:delta].to_f)}° cost=#{format("%.2f", wheel[:cost].to_f)} pose=(#{format_point(wheel[:x])}, #{format_point(wheel[:y])}) f#{format("%.1f", wheel[:facing].to_f)}°"
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
