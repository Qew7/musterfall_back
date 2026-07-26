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
            engagement = Geometry::Battlefield.charge_destination(combatant, nearest, heading)
            travel = [ combatant[:movement].to_f, Geometry::Battlefield.distance_between(combatant, engagement) ].min
            next if travel <= 0.05

            destination = if travel + 0.05 >= Geometry::Battlefield.distance_between(combatant, engagement)
              engagement
            else
              Geometry::Battlefield.move_along_facing(combatant.merge(facing: heading), travel)
            end
            projected = combatant.merge(x: destination[:x], y: destination[:y], facing: destination[:facing])
            blocked = acting_side[:combatants].any? do |entry|
              entry[:current_health].to_i > 0 &&
                entry[:entity_id] != combatant[:entity_id] &&
                Geometry::Battlefield.distance_between_units(projected, entry) < CONTACT
            end
            next if blocked

            from = position_of(combatant)
            before = State.snapshot_combatant(combatant)
            combatant[:x] = destination[:x]
            combatant[:y] = destination[:y]
            combatant[:facing] = destination[:facing]
            moved += 1
            after = State.snapshot_combatant(combatant)
            push_move!(phase, acting_side, target_side, combatant, before, after, from, "#{combatant[:name]} сближается с #{nearest[:name]}.")
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

        def push_move!(phase, acting_side, target_side, combatant, before, after, from, summary)
          to = position_of(combatant)
          AttackResolution.add_event(phase, summary)
          phase[:actions] << {
            type: "movement",
            actor_id: combatant[:entity_id],
            actor_name: combatant[:name],
            actor_state_before: before,
            actor_state_after: after,
            summary: summary,
            details: [
              "#{combatant[:name]} до движения: #{before[:row]}/#{before[:lane]}, facing #{before[:facing]}, HP #{before[:current_health]}/#{before[:max_health]}, моделей #{before[:models_remaining]}",
              "Маршрут: (#{format_point(from[:x])}, #{format_point(from[:y])}) -> (#{format_point(to[:x])}, #{format_point(to[:y])})",
              "#{combatant[:name]} после движения: #{after[:row]}/#{after[:lane]}, facing #{after[:facing]}, HP #{after[:current_health]}/#{after[:max_health]}, моделей #{after[:models_remaining]}"
            ],
            from: from,
            to: to,
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
