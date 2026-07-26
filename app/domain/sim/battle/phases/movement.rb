module Sim
  module Battle
    module Phases
      module Movement
        ADVANCING = { "rear" => "support", "support" => "front" }.freeze
        CONTACT = Geometry::Battlefield::CONFIG[:melee_contact_tolerance]

        module_function

        def play(acting_side:, target_side:, **)
          phase = AttackResolution.create_phase("movement", "Фаза движения")
          mobile = acting_side[:combatants]
            .select { |entry| entry[:current_health].to_i > 0 }
            .reject { |entry| entry[:is_routing] }
            .select { |entry| entry[:melee].to_i > entry[:ranged].to_i + entry[:spell].to_i }

          obstacles = active_units(acting_side[:combatants]) + active_units(target_side[:combatants])
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

            projected = State.project_combatant_position(combatant[:side_index], target_row, combatant[:lane], combatant[:facing])
            # Keep current facing: battle_position mirrors deployment facing again for the right side.
            advanced = combatant.merge(x: projected[:x], y: projected[:y], row: target_row)
            next if blocked_by_others?(advanced, obstacles, contact_id: nil)

            from = position_of(combatant)
            before = State.snapshot_combatant(combatant)
            combatant[:row] = target_row
            combatant[:x] = projected[:x]
            combatant[:y] = projected[:y]
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
                desired: { x: projected[:x], y: projected[:y], facing: combatant[:facing] },
                truncated_by_collision: false
              }
            )
          end

          mobile.each do |combatant|
            nearest = nearest_enemy(combatant, target_side[:combatants])
            next unless nearest
            next if Geometry::Battlefield.distance_between_units(combatant, nearest) <= CONTACT

            heading = Geometry::Battlefield.heading_to(combatant, nearest)
            budget = combatant[:movement].to_f
            wheel = Geometry::Battlefield.apply_wheel(combatant, heading, budget)
            wheeled = combatant.merge(x: wheel[:x], y: wheel[:y], facing: wheel[:facing])
            remaining = wheel[:remaining]

            desired = if remaining > 0.05 && wheel[:completed]
              engagement = Geometry::Battlefield.charge_destination(wheeled, nearest, wheel[:facing])
              distance = Geometry::Battlefield.distance_between(wheeled, engagement)
              if remaining + 0.05 >= distance
                engagement
              else
                Geometry::Battlefield.move_along_facing(wheeled, remaining)
              end
            elsif remaining > 0.05
              Geometry::Battlefield.move_along_facing(wheeled, remaining)
            else
              wheeled
            end

            clearance = furthest_clear_pose(combatant, wheel, desired, obstacles, contact_id: nearest[:entity_id])
            destination = clearance[:pose]
            next unless destination

            facing_changed = Geometry::Battlefield.shortest_facing_delta(combatant[:facing], destination[:facing]).abs > 0.05
            traveled = Geometry::Battlefield.distance_between(combatant, destination)
            next if !facing_changed && traveled <= 0.05

            from = position_of(combatant)
            before = State.snapshot_combatant(combatant)
            origin_pose = combatant.dup
            combatant[:x] = destination[:x]
            combatant[:y] = destination[:y]
            combatant[:facing] = destination[:facing]
            moved += 1
            after = State.snapshot_combatant(combatant)
            applied_wheel = wheel_for_applied_move(origin_pose, destination, wheel)
            march_spent = Geometry::Battlefield.distance_between(
              applied_wheel ? { x: applied_wheel[:x], y: applied_wheel[:y] } : origin_pose,
              destination
            )
            wheel_note = applied_wheel && applied_wheel[:cost].to_f > 0.05 ? " (wheel #{format("%.1f", applied_wheel[:cost])} MV)" : ""
            truncated = clearance[:truncated]
            block_note = truncated && clearance[:blocker] ? ", упёрся в #{clearance[:blocker][:name]}" : ""
            push_move!(
              phase,
              acting_side,
              target_side,
              combatant,
              before,
              after,
              from,
              "#{combatant[:name]} сближается с #{nearest[:name]}#{wheel_note}#{block_note}.",
              wheel: applied_wheel,
              maneuver: {
                kind: maneuver_kind(applied_wheel, march_spent),
                target_id: nearest[:entity_id],
                target_name: nearest[:name],
                heading: heading,
                desired_facing: heading,
                mv_budget: budget,
                mv_spent_wheel: applied_wheel ? applied_wheel[:cost].to_f : 0.0,
                mv_spent_march: march_spent,
                desired: { x: desired[:x], y: desired[:y], facing: desired[:facing] },
                truncated_by_collision: truncated,
                blocker_id: clearance.dig(:blocker, :entity_id),
                blocker_name: clearance.dig(:blocker, :name),
                wheel_direction: wheel_direction(applied_wheel)
              }
            )
          end

          AttackResolution.add_event(phase, "Строй удерживает позиции.") if moved.zero?
          phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          phase
        end

        def nearest_enemy(combatant, enemies)
          candidates = active_units(enemies)
          return nil if candidates.empty?

          candidates.min_by { |entry| [ entry[:is_routing] ? 0 : 1, Geometry::Battlefield.distance_between_units(combatant, entry) ] }
        end

        def active_units(combatants)
          combatants.select { |entry| entry[:current_health].to_i > 0 }
        end

        def first_blocker(projected, obstacles, contact_id:)
          obstacles.find do |entry|
            next false if entry[:entity_id] == projected[:entity_id]
            next false if entry[:current_health].to_i <= 0

            dist = Geometry::Battlefield.distance_between_units(projected, entry)
            if contact_id && entry[:entity_id] == contact_id
              Geometry::Battlefield.rectangles_overlap?(projected, entry)
            else
              dist < CONTACT
            end
          end
        end

        def blocked_by_others?(projected, obstacles, contact_id:)
          !first_blocker(projected, obstacles, contact_id: contact_id).nil?
        end

        # Walk wheel samples then the forward march; keep the furthest pose that does not clip anyone.
        def furthest_clear_pose(origin, wheel, destination, obstacles, contact_id:)
          samples = []
          if wheel[:delta].to_f.abs > 0.05
            steps = [ 8, (wheel[:delta].abs / 10).ceil ].max
            steps.times do |index|
              progress = (index + 1).to_f / steps
              pose = Geometry::Battlefield.wheel_pose(origin, wheel[:delta] * progress)
              samples << origin.merge(x: pose[:x], y: pose[:y], facing: pose[:facing])
            end
          end

          wheeled = if samples.any?
            samples.last
          else
            origin.merge(x: wheel[:x], y: wheel[:y], facing: wheel[:facing])
          end

          march_distance = Geometry::Battlefield.distance_between(wheeled, destination)
          facing_delta = Geometry::Battlefield.shortest_facing_delta(wheeled[:facing], destination[:facing]).abs
          if march_distance > 0.05 || facing_delta > 0.05
            steps = [ 8, (march_distance / 0.25).ceil ].max
            steps.times do |index|
              t = (index + 1).to_f / steps
              samples << wheeled.merge(
                x: wheeled[:x] + ((destination[:x] - wheeled[:x]) * t),
                y: wheeled[:y] + ((destination[:y] - wheeled[:y]) * t),
                facing: destination[:facing]
              )
            end
          elsif samples.empty?
            samples << wheeled.merge(x: destination[:x], y: destination[:y], facing: destination[:facing])
          end

          last_clear = nil
          blocker = nil
          samples.each do |pose|
            hit = first_blocker(pose, obstacles, contact_id: contact_id)
            if hit
              blocker = hit
              break
            end

            last_clear = pose
          end

          truncated = !blocker.nil? || (
            last_clear && (
              Geometry::Battlefield.distance_between(last_clear, destination) > 0.05 ||
              Geometry::Battlefield.shortest_facing_delta(last_clear[:facing], destination[:facing]).abs > 0.05
            )
          )

          { pose: last_clear, truncated: truncated, blocker: blocker }
        end

        def wheel_for_applied_move(origin, destination, planned_wheel)
          return nil unless planned_wheel && planned_wheel[:cost].to_f > 0.05

          applied_delta = Geometry::Battlefield.shortest_facing_delta(origin[:facing], destination[:facing])
          return nil if applied_delta.abs < 0.05
          return planned_wheel if Geometry::Battlefield.shortest_facing_delta(destination[:facing], planned_wheel[:facing]).abs < 0.05

          width = Geometry::Battlefield.unit_dimensions(origin)[:half_width] * 2.0
          cost = (applied_delta.abs * Math::PI / 180.0) * width
          {
            x: destination[:x],
            y: destination[:y],
            facing: destination[:facing],
            delta: applied_delta,
            cost: cost
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

        def push_move!(phase, acting_side, target_side, combatant, before, after, from, summary, wheel: nil, maneuver: nil)
          to = position_of(combatant)
          AttackResolution.add_event(phase, summary)
          facing_delta = Geometry::Battlefield.shortest_facing_delta(from[:facing], to[:facing])
          details = [
            "#{combatant[:name]} до движения: #{before[:row]}/#{before[:lane]}, facing #{format("%.1f", before[:facing])}°, HP #{before[:current_health]}/#{before[:max_health]}, моделей #{before[:models_remaining]}",
            "Маршрут: (#{format_point(from[:x])}, #{format_point(from[:y])}) -> (#{format_point(to[:x])}, #{format_point(to[:y])}), Δfacing #{format("%+.1f", facing_delta)}°",
            "#{combatant[:name]} после движения: #{after[:row]}/#{after[:lane]}, facing #{format("%.1f", after[:facing])}°, HP #{after[:current_health]}/#{after[:max_health]}, моделей #{after[:models_remaining]}"
          ]
          if wheel && wheel[:cost].to_f > 0.05
            direction = wheel_direction(wheel)
            details.insert(
              1,
              "Манёвр wheel #{direction || "?"} #{format("%+.0f", wheel[:delta])}° за #{format("%.1f", wheel[:cost])} MV -> (#{format_point(wheel[:x])}, #{format_point(wheel[:y])}), facing #{format("%.0f", wheel[:facing])}°"
            )
          end
          if maneuver
            details.insert(1, maneuver_detail_line(maneuver))
          end

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

        def maneuver_detail_line(maneuver)
          parts = [ "Тип манёвра: #{maneuver[:kind]}" ]
          if maneuver[:target_name]
            parts << "цель #{maneuver[:target_name]} (heading #{format("%.0f", maneuver[:heading].to_f)}°)"
          end
          if maneuver[:mv_budget]
            parts << "MV wheel/march/budget #{format("%.1f", maneuver[:mv_spent_wheel].to_f)}/#{format("%.1f", maneuver[:mv_spent_march].to_f)}/#{format("%.1f", maneuver[:mv_budget].to_f)}"
          end
          if maneuver[:desired]
            desired = maneuver[:desired]
            parts << "желаемо (#{format_point(desired[:x])}, #{format_point(desired[:y])}) f#{format("%.0f", desired[:facing].to_f)}°"
          end
          if maneuver[:truncated_by_collision]
            blocker = maneuver[:blocker_name] ? " об #{maneuver[:blocker_name]}" : ""
            parts << "путь укорочен из-за коллизии#{blocker}"
          end
          parts.join("; ")
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
