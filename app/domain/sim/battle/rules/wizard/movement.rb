module Sim
  module Battle
    module Rules
      module Wizard
        # Casters who cannot cast from the current pose walk toward a valid spell anchor.
        module Movement
          # rule: wizard | movement | Casters path toward spell anchor when no valid cast is available.
          module_function

          def caster?(combatant)
            return true if combatant[:spell].to_i.positive? && Array(combatant[:spell_keys]).any?

            Array(combatant.dig(:contributors, :ranged)).any? do |contributor|
              contributor[:spell].to_i.positive? && Array(contributor[:spell_keys]).any?
            end
          end

          def opens_cast?(host, acting_side:, target_side:, terrain: [], round_number: 1)
            return false unless caster?(host)

            side = posed_side(acting_side, host)
            all = side[:combatants] + target_side[:combatants]
            return false if Decisions::Targeting.in_melee_combat?(host, all)

            rng = Sim::Rng::Seeded.new(0)
            SpellCasting.casters(side).any? do |entry|
              next false unless entry[:host][:entity_id] == host[:entity_id]

              caster = entry[:caster].merge(x: host[:x], y: host[:y], facing: host[:facing])
              SpellCasting.choose_spell(
                caster: caster,
                host: host,
                acting_side: side,
                target_side: target_side,
                round_number: round_number,
                rng: rng,
                terrain: terrain
              )
            end
          end

          def seek_goals(combatant, acting_side:, target_side:, budget:, terrain: [])
            anchor = seek_anchor(combatant, acting_side, target_side)
            return [] unless anchor

            heading = Geometry::Battlefield.heading_to(combatant, anchor)
            forward = Geometry::Battlefield.facing_vector(heading)
            right = Geometry::Battlefield.right_vector(heading)
            step = [ budget.to_f, 0.05 ].max
            direct = [ 0.0, 1.0, -1.0 ].map do |sign|
              Geometry::Battlefield.clamp_battlefield_position(
                x: combatant[:x].to_f + (forward[:x] * step * 0.9) + (right[:x] * step * 0.2 * sign),
                y: combatant[:y].to_f + (forward[:y] * step * 0.9) + (right[:y] * step * 0.2 * sign),
                facing: heading
              )
            end
            bypass = seek_bypass_goals(combatant, anchor, heading, acting_side, target_side, terrain)
            (bypass + direct).uniq { |goal| [ goal[:x].round(2), goal[:y].round(2) ] }
              .first(Sim::Battle::Decisions::Reposition::MAX_PATH_ATTEMPTS)
          end

          def seek_bypass_goals(combatant, anchor, heading, acting_side, target_side, terrain)
            return [] if Array(terrain).empty?

            board = Decisions::Roles.standing(acting_side[:combatants]) +
              Decisions::Roles.standing(target_side[:combatants])
            world = Pathing::Obstacles.around(combatant, units: board, terrain: terrain)
            thread = Pathing::Thread.pull(mover: combatant, goal: anchor, world: world)
            return [] if Array(thread[:wrapped]).empty? || Array(thread[:points]).length < 2

            Array(thread[:points]).drop(1).map do |point|
              Geometry::Battlefield.clamp_battlefield_position(
                x: point[:x],
                y: point[:y],
                facing: heading
              )
            end
          end
          private_class_method :seek_bypass_goals

          def improves_seek?(origin, candidate, acting_side:, target_side:, terrain: [], round_number: 1)
            if opens_cast?(candidate, acting_side: acting_side, target_side: target_side, terrain: terrain, round_number: round_number) &&
                !opens_cast?(origin, acting_side: acting_side, target_side: target_side, terrain: terrain, round_number: round_number)
              return true
            end

            anchor = seek_anchor(origin, acting_side, target_side)
            return false unless anchor

            Geometry::Battlefield.distance_between(candidate, anchor) <
              Geometry::Battlefield.distance_between(origin, anchor) - 0.05
          end

          def seek_anchor(host, acting_side, target_side)
            types = spell_target_types(host)
            if (types & %i[enemy_unit enemy_caster battlefield_point]).any?
              return Decisions::Roles.standing(target_side[:combatants])
                .min_by { |entry| Geometry::Battlefield.distance_between(host, entry) }
            end

            if types.include?(:damaged_ally_unit)
              damaged = Decisions::Roles.standing(acting_side[:combatants]).select do |entry|
                entry[:current_health].to_i < entry[:max_health].to_i
              end
              pool = damaged.presence || Decisions::Roles.standing(acting_side[:combatants])
              return pool.reject { |entry| entry[:entity_id] == host[:entity_id] }
                .min_by { |entry| Geometry::Battlefield.distance_between(host, entry) }
            end

            Decisions::Roles.standing(acting_side[:combatants] + target_side[:combatants])
              .reject { |entry| entry[:entity_id] == host[:entity_id] }
              .min_by { |entry| Geometry::Battlefield.distance_between(host, entry) }
          end

          def posed_side(acting_side, host)
            acting_side.merge(
              combatants: acting_side[:combatants].map do |entry|
                entry[:entity_id] == host[:entity_id] ? host : entry
              end
            )
          end

          def spell_target_types(host)
            keys = Array(host[:spell_keys])
            if keys.empty?
              keys = Array(host.dig(:contributors, :ranged)).flat_map { |entry| Array(entry[:spell_keys]) }
            end
            keys.filter_map { |key| Spells.fetch(key)&.target_type&.to_sym }.uniq
          end
        end
      end
    end
  end
end
