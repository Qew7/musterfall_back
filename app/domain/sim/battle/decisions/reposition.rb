module Sim
  module Battle
    module Decisions
      # Fast ranged/mage reposition: a few geometric goals, one pathing call each.
      module Reposition
        CONTACT = Geometry::Battlefield::CONFIG[:melee_contact_tolerance]
        MAX_PATH_ATTEMPTS = 3

        module_function

        def seekers(acting_side:, target_side:, round_number:)
          enemies = target_side[:combatants]
          all = acting_side[:combatants] + enemies
          Roles.active(acting_side[:combatants]).select do |host|
            next false if host[:movement].to_f <= 0.05

            # Cheap geometric filters first; avoid full MissileChoice damage scans here.
            next true if in_charge_danger?(host, enemies)
            next true if under_missile_threat?(host, enemies)
            next false unless Roles.missile_seeker?(host)

            !cheap_opens_shot?(host, enemies, all)
          end
        end

        def build_intent(combatant:, acting_side:, target_side:, obstacles:, round_number:, terrain: [])
          allies = acting_side[:combatants]
          enemies = target_side[:combatants]
          all = allies + enemies
          budget = Decisions::Movement.budget_for(combatant, enemies: enemies)
          return nil if budget <= 0.05

          mode = primary_mode(combatant, enemies, all, round_number)
          march_meta = Decisions::Movement.budget_meta(combatant, enemies: enemies)

          candidate_goals(combatant, allies, enemies, all, round_number, mode, terrain: terrain).each do |goal|
            plan = Pathing.plan_approach(
              origin: combatant,
              goal_point: goal,
              budget: budget,
              obstacles: obstacles,
              contact_id: nil,
              goal_unit: nil,
              bypass: false,
              terrain: terrain,
              flying: Decisions::Movement.flying?(combatant),
              march_allowed: march_meta[:march].to_s == "active"
            )
            pose = plan[:pose]
            next unless pose && meaningful?(combatant, pose)
            next unless clear_pose?(pose.merge(entity_id: combatant[:entity_id]), obstacles)

            candidate = apply_pose(combatant, pose)
            unless mode == :escape_charge
              candidate, plan = face_if_clear(combatant, candidate, plan, budget, enemies, all, obstacles)
            end
            next unless improves?(combatant, candidate, allies, enemies, all, mode)

            # First improving pose for the primary need is enough — no combinatorial search.
            return intent_for(combatant, candidate, plan, budget, enemies, all, march_meta: march_meta)
          end

          return nil if mode == :escape_charge

          hold_wheel_intent(combatant, allies, enemies, all, budget, obstacles)
        end

        def primary_mode(combatant, enemies, all, _round_number)
          return :escape_charge if in_charge_danger?(combatant, enemies)
          return :leave_shot if under_missile_threat?(combatant, enemies)
          return :open_los if Roles.missile_seeker?(combatant) && !cheap_opens_shot?(combatant, enemies, all)

          :hold
        end

        def candidate_goals(combatant, _allies, enemies, all, round_number, mode, terrain: [])
          goals =
            case mode
            when :escape_charge then escape_charge_goals(combatant, enemies)
            when :leave_shot then leave_shot_goals(combatant, enemies)
            when :open_los then open_los_goals(combatant, enemies, all, terrain: terrain)
            else []
            end
          goals.compact.first(MAX_PATH_ATTEMPTS)
        end

        def escape_charge_goals(combatant, enemies)
          threats = Roles.standing(enemies).select { |enemy| Roles.melee_primary?(enemy) }
          return [] if threats.empty?

          away = heading_away_from(combatant, threats)
          step = Decisions::Movement.budget_for(combatant, enemies: threats)
          # Pure retreat often stays inside a 120° front arc; oblique headings exit range/arc cheaper.
          [ away, away + 45, away - 45, away + 30, away - 30 ].map do |heading|
            vector = Geometry::Battlefield.facing_vector(heading)
            Geometry::Battlefield.clamp_battlefield_position(
              x: combatant[:x].to_f + (vector[:x] * step),
              y: combatant[:y].to_f + (vector[:y] * step),
              facing: Geometry::Battlefield.normalize_facing(heading)
            )
          end
        end

        def leave_shot_goals(combatant, enemies)
          shooter = Roles.standing(enemies)
            .select { |enemy| enemy[:ranged].to_i > 0 || enemy[:spell].to_i > 0 }
            .min_by { |enemy| center_dist2(combatant, enemy) }
          return [] unless shooter

          right = Geometry::Battlefield.right_vector(shooter[:facing])
          forward = Geometry::Battlefield.facing_vector(shooter[:facing])
          step = Decisions::Movement.budget_for(combatant, enemies: [ shooter ])
          # Exit the shooter's front arc: lateral + slight forward/back so angle clears 60°.
          [ 1, -1 ].flat_map do |sign|
            [
              Geometry::Battlefield.clamp_battlefield_position(
                x: combatant[:x].to_f + (right[:x] * step * 0.75 * sign) - (forward[:x] * step * 0.5),
                y: combatant[:y].to_f + (right[:y] * step * 0.75 * sign) - (forward[:y] * step * 0.5),
                facing: combatant[:facing]
              ),
              Geometry::Battlefield.clamp_battlefield_position(
                x: combatant[:x].to_f + (right[:x] * step * sign),
                y: combatant[:y].to_f + (right[:y] * step * sign),
                facing: combatant[:facing]
              )
            ]
          end
        end

        def open_los_goals(combatant, enemies, all, terrain: [])
          target = best_potential_target(combatant, enemies, all)
          return [] unless target

          heading = Geometry::Battlefield.heading_to(combatant, target)
          right = Geometry::Battlefield.right_vector(heading)
          step = [ Decisions::Movement.budget_for(combatant, enemies: enemies) * 0.55, 2.5 ].min
          # Oblique goals: clear the blocker while ending roughly facing the target.
          [ 1, -1 ].flat_map do |sign|
            [ 0.6, 1.0 ].map do |scale|
              Geometry::Battlefield.clamp_battlefield_position(
                x: combatant[:x].to_f + (right[:x] * step * scale * sign) +
                  (Geometry::Battlefield.facing_vector(heading)[:x] * step * 0.45 * scale),
                y: combatant[:y].to_f + (right[:y] * step * scale * sign) +
                  (Geometry::Battlefield.facing_vector(heading)[:y] * step * 0.45 * scale),
                facing: heading
              )
            end
          end
        end

        def hold_wheel_intent(combatant, allies, enemies, all, budget, obstacles)
          target = best_potential_target(combatant, enemies, all)
          return nil unless target

          facing = Geometry::Battlefield.heading_to(combatant, target)
          return nil if Geometry::Battlefield.shortest_facing_delta(combatant[:facing], facing).abs < 0.05

          wheeled = try_face_clear(combatant, combatant, facing, budget, obstacles)
          return nil unless wheeled

          candidate = apply_pose(combatant, wheeled[:pose])
          return nil unless improves?(combatant, candidate, allies, enemies, all, :hold)

          intent_for(combatant, candidate, wheeled[:plan], budget, enemies, all, march_meta: Decisions::Movement.budget_meta(combatant, enemies: enemies))
        end

        def face_if_clear(origin, candidate, plan, budget, enemies, all, obstacles)
          look = preferred_facing(candidate, enemies, all)
          return [ candidate, plan ] unless look

          remaining = remaining_after_plan(origin, candidate, plan, budget)
          faced = try_face_clear(candidate, candidate, look, remaining, obstacles)
          return [ candidate, plan ] unless faced

          [ apply_pose(candidate, faced[:pose]), faced[:plan].merge(
            desired: plan[:desired] || faced[:pose],
            heading: plan[:heading],
            truncated: plan[:truncated],
            avoided: plan[:avoided],
            blocked_by_ally: plan[:blocked_by_ally],
            blocker: plan[:blocker]
          ) ]
        end

        def try_face_clear(origin, pose_unit, desired_facing, budget, obstacles)
          spent = Geometry::Battlefield.distance_between(origin, pose_unit)
          remaining = budget - spent
          return nil if remaining <= 0.05

          wheel_cost = Geometry::Battlefield.wheel_cost(pose_unit, pose_unit[:facing], desired_facing)
          return nil if wheel_cost > remaining + 0.05

          wheeled = Geometry::Battlefield.apply_wheel(pose_unit, desired_facing, remaining)
          return nil unless wheeled[:completed] || Geometry::Battlefield.shortest_facing_delta(wheeled[:facing], desired_facing).abs < 1.0

          faced = pose_unit.merge(x: wheeled[:x], y: wheeled[:y], facing: wheeled[:facing])
          return nil unless clear_pose?(faced, obstacles)

          {
            pose: faced,
            plan: {
              pose: faced,
              desired: faced,
              heading: desired_facing,
              avoided: false,
              truncated: false,
              blocked_by_ally: false,
              blocker: nil,
              wheel: {
                x: wheeled[:x],
                y: wheeled[:y],
                facing: wheeled[:facing],
                delta: wheeled[:delta],
                cost: wheeled[:cost]
              }
            }
          }
        end

        def improves?(origin, candidate, allies, enemies, all, mode = nil)
          case mode
          when :escape_charge
            return !in_charge_danger?(candidate, enemies) if in_charge_danger?(origin, enemies)

            false
          when :leave_shot
            missile_threat_count(candidate, enemies) < missile_threat_count(origin, enemies)
          when :open_los, :hold
            return true if cheap_opens_shot?(candidate, enemies, replace_unit(all, candidate)) &&
              !cheap_opens_shot?(origin, enemies, all)

            false
          else
            before = snapshot_metrics(origin, enemies, all)
            after = snapshot_metrics(candidate, enemies, replace_unit(all, candidate))
            return true if after[:charge] > before[:charge]
            return true if after[:threat] < before[:threat]
            return true if after[:shot] > before[:shot]

            false
          end
        end

        def snapshot_metrics(pose_unit, enemies, all)
          {
            charge: in_charge_danger?(pose_unit, enemies) ? 0 : 1,
            threat: missile_threat_count(pose_unit, enemies),
            shot: cheap_opens_shot?(pose_unit, enemies, all) ? 1 : 0
          }
        end

        def intent_for(combatant, candidate, plan, budget, enemies, all, march_meta: {})
          target = best_potential_target(candidate, enemies, all)
          {
            kind: "reposition",
            combatant: combatant,
            plan: plan,
            budget: budget,
            march_meta: march_meta,
            destination: { x: candidate[:x], y: candidate[:y], facing: candidate[:facing] },
            wait: false,
            nearest: target
          }
        end

        def clear_pose?(pose_unit, obstacles)
          Pathing.first_blocker(pose_unit, obstacles, contact_id: nil, origin: pose_unit).nil?
        end

        def remaining_after_plan(origin, pose_unit, plan, budget)
          wheel_cost = plan[:wheel] ? plan[:wheel][:cost].to_f : 0.0
          wheel_pose = plan[:wheel] ? { x: plan[:wheel][:x], y: plan[:wheel][:y] } : origin
          march = Geometry::Battlefield.distance_between(wheel_pose, pose_unit)
          [ budget - wheel_cost - march, 0.0 ].max
        end

        def in_charge_danger?(pose_unit, enemies)
          px = pose_unit[:x].to_f
          py = pose_unit[:y].to_f
          Roles.standing(enemies).any? do |enemy|
            next false unless Roles.melee_primary?(enemy)

            reach = enemy[:movement].to_f + CONTACT
            # Center reject before expensive OBB distance.
            dx = px - enemy[:x].to_f
            dy = py - enemy[:y].to_f
            next false if ((dx * dx) + (dy * dy)) > ((reach + 4.0) * (reach + 4.0))
            next false unless Geometry::Battlefield.in_front_arc?(enemy, pose_unit, enemy[:facing])

            Geometry::Battlefield.distance_between_units(pose_unit, enemy) <= reach
          end
        end

        def under_missile_threat?(unit, enemies)
          missile_threat_count(unit, enemies).positive?
        end

        def missile_threat_count(unit, enemies)
          Roles.standing(enemies).count do |enemy|
            if enemy[:ranged].to_i > 0
              Geometry::Battlefield.in_front_arc?(enemy, unit, enemy[:facing]) &&
                Geometry::Battlefield.line_of_sight_blockers(enemy, unit, [ enemy, unit ]).empty?
            elsif enemy[:spell].to_i > 0
              range = enemy[:spell_range].to_f
              range <= 0 || Geometry::Battlefield.distance_between_units(enemy, unit) <= range
            else
              false
            end
          end
        end

        def cheap_opens_shot?(pose_unit, enemies, all_combatants)
          board = replace_unit(all_combatants, pose_unit)
          actors_for(pose_unit).any? do |actor|
            posed = actor.merge(x: pose_unit[:x], y: pose_unit[:y], facing: pose_unit[:facing])
            can_shoot = posed[:ranged].to_i > 0
            can_cast = posed[:spell].to_i > 0
            next false unless can_shoot || can_cast

            Roles.standing(enemies).any? do |enemy|
              next false if Targeting.in_melee_combat?(enemy, board)
              next true if can_cast

              next false if Rules.for(:shooting).requires_front_arc_for_ranged?(posed) &&
                !Geometry::Battlefield.in_front_arc?(posed, enemy, posed[:facing])

              Geometry::Battlefield.line_of_sight_blockers(posed, enemy, board).empty?
            end
          end
        end

        def preferred_facing(pose_unit, enemies, _all_combatants = nil)
          target = nearest_standing(pose_unit, enemies)
          return nil unless target

          Geometry::Battlefield.heading_to(pose_unit, target)
        end

        def best_potential_target(pose_unit, enemies, all_combatants)
          Roles.standing(enemies)
            .reject { |enemy| Targeting.in_melee_combat?(enemy, all_combatants) }
            .min_by { |enemy| center_dist2(pose_unit, enemy) }
        end

        def nearest_standing(pose_unit, enemies)
          Roles.standing(enemies).min_by { |enemy| center_dist2(pose_unit, enemy) }
        end

        def center_dist2(left, right)
          dx = left[:x].to_f - right[:x].to_f
          dy = left[:y].to_f - right[:y].to_f
          (dx * dx) + (dy * dy)
        end

        def heading_away_from(combatant, threats)
          center = threats.each_with_object(x: 0.0, y: 0.0) do |enemy, memo|
            memo[:x] += enemy[:x].to_f
            memo[:y] += enemy[:y].to_f
          end
          average = { x: center[:x] / threats.length, y: center[:y] / threats.length }
          Geometry::Battlefield.heading_to(average, combatant)
        end

        def actors_for(host)
          ranged = host.dig(:contributors, :ranged) || []
          ranged.filter_map do |contributor|
            next unless contributor[:ranged].to_i > 0 || contributor[:spell].to_i > 0

            MissileChoice.build_actor(host, contributor)
          end
        end

        def apply_pose(combatant, pose)
          combatant.merge(x: pose[:x], y: pose[:y], facing: pose[:facing])
        end

        def replace_unit(all_combatants, pose_unit)
          all_combatants.map { |entry| entry[:entity_id] == pose_unit[:entity_id] ? pose_unit : entry }
        end

        def meaningful?(origin, destination)
          Geometry::Battlefield.distance_between(origin, destination) > 0.05 ||
            Geometry::Battlefield.shortest_facing_delta(origin[:facing], destination[:facing]).abs > 0.05
        end
      end
    end
  end
end
