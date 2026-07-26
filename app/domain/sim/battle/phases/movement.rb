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

            from = position_of(combatant)
            before = State.snapshot_combatant(combatant)
            combatant[:row] = target_row
            combatant.merge!(State.project_combatant_position(combatant[:side_index], target_row, combatant[:lane], combatant[:facing]))
            moved += 1
            after = State.snapshot_combatant(combatant)
            push_move!(phase, acting_side, target_side, combatant, before, after, from, "#{combatant[:name]} выдвигается в ряд #{target_row}.")
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

            destination = if remaining > 0.05 && wheel[:completed]
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

            facing_changed = Geometry::Battlefield.shortest_facing_delta(combatant[:facing], destination[:facing]).abs > 0.05
            traveled = Geometry::Battlefield.distance_between(combatant, destination)
            next if !facing_changed && traveled <= 0.05
            next if wheel_path_blocked?(combatant, wheel, destination, acting_side[:combatants])

            from = position_of(combatant)
            before = State.snapshot_combatant(combatant)
            combatant[:x] = destination[:x]
            combatant[:y] = destination[:y]
            combatant[:facing] = destination[:facing]
            moved += 1
            after = State.snapshot_combatant(combatant)
            wheel_note = wheel[:cost] > 0.05 ? " (wheel #{format("%.1f", wheel[:cost])} MV)" : ""
            push_move!(
              phase,
              acting_side,
              target_side,
              combatant,
              before,
              after,
              from,
              "#{combatant[:name]} сближается с #{nearest[:name]}#{wheel_note}.",
              wheel: wheel
            )
          end

          AttackResolution.add_event(phase, "Строй удерживает позиции.") if moved.zero?
          phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          phase
        end

        def nearest_enemy(combatant, enemies)
          living = enemies.select { |entry| entry[:current_health].to_i > 0 }
          return nil if living.empty?

          living.min_by { |entry| [ entry[:is_routing] ? 0 : 1, Geometry::Battlefield.distance_between_units(combatant, entry) ] }
        end

        def wheel_path_blocked?(origin, wheel, destination, allies)
          samples = []
          if wheel[:delta].to_f.abs > 0.05
            steps = [ 3, (wheel[:delta].abs / 15).ceil ].max
            steps.times do |index|
              progress = (index + 1).to_f / steps
              samples << Geometry::Battlefield.wheel_pose(origin, wheel[:delta] * progress)
            end
          end
          samples << destination

          samples.any? do |pose|
            projected = origin.merge(x: pose[:x], y: pose[:y], facing: pose[:facing])
            allies.any? do |entry|
              entry[:current_health].to_i > 0 &&
                entry[:entity_id] != origin[:entity_id] &&
                Geometry::Battlefield.distance_between_units(projected, entry) < CONTACT
            end
          end
        end

        def push_move!(phase, acting_side, target_side, combatant, before, after, from, summary, wheel: nil)
          to = position_of(combatant)
          AttackResolution.add_event(phase, summary)
          details = [
            "#{combatant[:name]} до движения: #{before[:row]}/#{before[:lane]}, facing #{before[:facing]}, HP #{before[:current_health]}/#{before[:max_health]}, моделей #{before[:models_remaining]}",
            "Маршрут: (#{format_point(from[:x])}, #{format_point(from[:y])}) -> (#{format_point(to[:x])}, #{format_point(to[:y])})",
            "#{combatant[:name]} после движения: #{after[:row]}/#{after[:lane]}, facing #{after[:facing]}, HP #{after[:current_health]}/#{after[:max_health]}, моделей #{after[:models_remaining]}"
          ]
          if wheel && wheel[:cost].to_f > 0.05
            details.insert(
              1,
              "Wheel #{format("%.0f", wheel[:delta])}° за #{format("%.1f", wheel[:cost])} MV -> (#{format_point(wheel[:x])}, #{format_point(wheel[:y])}), facing #{format("%.0f", wheel[:facing])}"
            )
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
            wheel: wheel && wheel[:cost].to_f > 0.05 ? { x: wheel[:x], y: wheel[:y], facing: wheel[:facing], delta: wheel[:delta], cost: wheel[:cost] } : nil,
            snapshot: State.snapshot_battlefield([ acting_side, target_side ])
          }
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
