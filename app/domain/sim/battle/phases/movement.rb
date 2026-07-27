module Sim
  module Battle
    module Phases
      module Movement
        ADVANCING = { "rear" => "support", "support" => "front" }.freeze
        CONTACT = Pathing::CONTACT

        module_function

        def play(acting_side:, target_side:, **)
          phase = AttackResolution.create_phase("movement", "Фаза движения")
          mobile = acting_side[:combatants]
            .select { |entry| entry[:current_health].to_i > 0 }
            .reject { |entry| entry[:is_routing] }
            .select { |entry| entry[:melee].to_i > entry[:ranged].to_i + entry[:spell].to_i }

          obstacles = Pathing.active_units(acting_side[:combatants]) + Pathing.active_units(target_side[:combatants])
          moved = 0
          mobile.each do |combatant|
            target_row = ADVANCING[combatant[:row]]
            next unless target_row

            occupied = acting_side[:combatants].any? do |entry|
              entry[:current_health].to_i > 0 &&
                entry[:entity_id] != combatant[:entity_id] &&
                entry[:lane] == combatant[:lane] &&
                entry[:row] == target_row
            end
            next if occupied

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

          mobile.each do |combatant|
            nearest = nearest_enemy(combatant, target_side[:combatants])
            next unless nearest
            next if Geometry::Battlefield.distance_between_units(combatant, nearest) <= CONTACT

            budget = combatant[:movement].to_f
            plan = Pathing.plan_approach(
              origin: combatant,
              goal_point: nearest,
              budget: budget,
              obstacles: obstacles,
              contact_id: nearest[:entity_id],
              goal_unit: nearest
            )
            destination = plan[:pose]
            facing_changed = destination && Geometry::Battlefield.shortest_facing_delta(combatant[:facing], destination[:facing]).abs > 0.05
            traveled = destination ? Geometry::Battlefield.distance_between(combatant, destination) : 0.0
            meaningful_move = destination && (facing_changed || traveled > 0.05)

            if !meaningful_move
              next unless plan[:blocked_by_ally] && plan[:blocker]

              from = position_of(combatant)
              before = State.snapshot_combatant(combatant)
              after = before
              moved += 1
              push_move!(
                phase,
                acting_side,
                target_side,
                combatant,
                before,
                after,
                from,
                "#{combatant[:name]} ждёт прохода у #{plan[:blocker][:name]}.",
                wheel: nil,
                maneuver: approach_maneuver(plan, nearest, budget, wheel: nil, march_spent: 0.0, desired: combatant),
                origin_pose: combatant
              )
              next
            end

            from = position_of(combatant)
            before = State.snapshot_combatant(combatant)
            origin_pose = combatant.dup
            combatant[:x] = destination[:x]
            combatant[:y] = destination[:y]
            combatant[:facing] = destination[:facing]
            moved += 1
            after = State.snapshot_combatant(combatant)

            planned_wheel = plan[:wheel]
            applied_wheel = wheel_for_applied_move(origin_pose, destination, planned_wheel)
            march_spent = Geometry::Battlefield.distance_between(
              applied_wheel ? { x: applied_wheel[:x], y: applied_wheel[:y] } : origin_pose,
              destination
            )
            desired = plan[:desired] || destination
            maneuver = approach_maneuver(plan, nearest, budget, wheel: applied_wheel, march_spent: march_spent, desired: desired)
            push_move!(
              phase,
              acting_side,
              target_side,
              combatant,
              before,
              after,
              from,
              approach_player_summary(combatant, nearest, plan),
              wheel: applied_wheel,
              maneuver: maneuver,
              origin_pose: origin_pose
            )
          end

          AttackResolution.add_event(phase, "Строй удерживает позиции.") if moved.zero?
          phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          phase
        end

        def nearest_enemy(combatant, enemies)
          candidates = Pathing.active_units(enemies)
          return nil if candidates.empty?

          candidates.min_by { |entry| [ entry[:is_routing] ? 0 : 1, Geometry::Battlefield.distance_between_units(combatant, entry) ] }
        end

        # Player-facing: short and truthful. Wheel MV / pathing flags belong in details.
        def approach_player_summary(combatant, nearest, plan)
          note = approach_player_note(plan, nearest)
          "#{combatant[:name]} сближается с #{nearest[:name]}#{note}."
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

        def approach_maneuver(plan, nearest, budget, wheel:, march_spent:, desired:)
          contact_blocker = blocker_is_target?(plan, nearest)
          kind = if plan[:blocked_by_ally]
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
            target_id: nearest[:entity_id],
            target_name: nearest[:name],
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
