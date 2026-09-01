module Sim
  module Battle
    module Rules
      module Flying
        # Flyer priority: rear charge → flank charge → front charge (if no rear setup) → rear setup → close.
        module Movement
          SETUP_CLEARANCE = 0.25

          module_function

          def plan_entries(movers, enemies, claimed, terrain: [])
            living = Pathing.active_units(enemies)
            ranked = movers.sort_by { |combatant| [ combatant[:entity_id].to_s ] }
            entries_by_id = {}

            ranked.each do |combatant|
              entry = plan_entry(combatant, living, claimed, terrain)
              next unless entry

              claimed[entry[:nearest][:entity_id]][entry[:contact_slot]] = combatant[:entity_id]
              entries_by_id[combatant[:entity_id]] = entry
            end

            ranked.filter_map { |combatant| entries_by_id[combatant[:entity_id]] }
          end

          # Own wave before infantry so landings exist as obstacles, not takeoff ghosts.
          def plan_waves(movers, enemies, claimed, terrain: [])
            entries = plan_entries(movers, enemies, claimed, terrain: terrain)
            return [] if entries.empty?

            [ { entries: entries, allow_ally_bypass: true } ]
          end

          def plan_entry(combatant, enemies, claimed, terrain = [])
            return nil if Decisions::Movement.engaged_with_any?(combatant, enemies)

            choose_charge_for_slot(combatant, enemies, claimed, terrain, "rear") ||
              choose_charge_for_slot(combatant, enemies, claimed, terrain, "flank") ||
              (!any_rear_setup_possible?(combatant, enemies, claimed, terrain) &&
                choose_charge_for_slot(combatant, enemies, claimed, terrain, "front")) ||
              choose_setup_rear(combatant, enemies, claimed, terrain) ||
              choose_approach(combatant, enemies, claimed, terrain)
          end

          def choose_charge_for_slot(combatant, enemies, claimed, terrain, slot)
            budget = Decisions::Movement.budget_for(combatant, enemies: enemies)
            return nil if budget <= 0.05

            enemy = furthest_chargeable_enemy(combatant, enemies, claimed, terrain, slot)
            return nil unless enemy

            chargeable = Decisions::Movement.can_charge?(combatant, enemy, terrain)
            Decisions::Movement.build_entry(combatant, enemy, slot, :flyer_charge, chargeable: chargeable)
          end

          def furthest_chargeable_enemy(combatant, enemies, claimed, terrain, slot)
            Pathing.active_units(enemies).select do |enemy|
              next false unless Decisions::Movement.can_charge?(combatant, enemy, terrain)
              next false if claimed[enemy[:entity_id]].key?(slot)
              next false unless Decisions::Movement.this_turn_charge?(combatant, enemy, enemies: enemies)

              true
            end.max_by do |enemy|
              [ Geometry::Battlefield.distance_between_units(combatant, enemy), enemy[:entity_id].to_s ]
            end
          end

          def any_rear_setup_possible?(combatant, enemies, claimed, terrain = [])
            budget = Decisions::Movement.budget_for(combatant, enemies: enemies)
            return false if budget <= 0.05

            living = Pathing.active_units(enemies)
            return false if living.empty?

            living.any? do |enemy|
              next false if %w[flank rear].include?(Geometry::Battlefield.classify_attack_vector(combatant, enemy))
              next false if claimed[enemy[:entity_id]].key?("rear")
              next false unless setup_goal_within_budget?(combatant, enemy, "rear", budget)

              blockers = living.reject { |unit| unit[:entity_id] == enemy[:entity_id] } + Array(terrain)
              setup_side_landable?(combatant, enemy, "rear", budget, blockers)
            end
          end

          def choose_setup_rear(combatant, enemies, claimed, terrain = [])
            budget = Decisions::Movement.budget_for(combatant, enemies: enemies)
            return nil if budget <= 0.05

            living = Pathing.active_units(enemies)
            return nil if living.empty?

            ordered = living.sort_by do |enemy|
              [
                -Geometry::Battlefield.distance_between_units(combatant, enemy),
                enemy[:entity_id].to_s
              ]
            end

            ordered.each do |enemy|
              next if %w[flank rear].include?(Geometry::Battlefield.classify_attack_vector(combatant, enemy))
              next if claimed[enemy[:entity_id]].key?("rear")
              next unless setup_goal_within_budget?(combatant, enemy, "rear", budget)

              pad_blockers = living.reject { |unit| unit[:entity_id] == enemy[:entity_id] } + Array(terrain)
              next unless setup_side_landable?(combatant, enemy, "rear", budget, pad_blockers)

              chargeable = Decisions::Movement.can_charge?(combatant, enemy, terrain)
              return Decisions::Movement.build_entry(combatant, enemy, "rear", :flyer_setup_rear, chargeable: chargeable)
            end
            nil
          end

          # Out of setup/charge range: still close toward rear/flank, staying off enemy front arcs.
          def choose_approach(combatant, enemies, claimed, terrain = [])
            budget = Decisions::Movement.budget_for(combatant, enemies: enemies)
            return nil if budget <= 0.05

            living = Pathing.active_units(enemies)
            return nil if living.empty?

            ordered = living.sort_by do |enemy|
              [
                Decisions::Movement.can_charge?(combatant, enemy, terrain) ? 0 : 1,
                enemy[:is_routing] ? 1 : 0,
                -Geometry::Battlefield.distance_between_units(combatant, enemy),
                enemy[:entity_id].to_s
              ]
            end

            ordered.each do |enemy|
              claimed_sides = claimed[enemy[:entity_id]]
              chargeable = Decisions::Movement.can_charge?(combatant, enemy, terrain)
              %w[rear flank].each do |slot|
                next if claimed_sides.key?(slot)

                return Decisions::Movement.build_entry(combatant, enemy, slot, :flyer_approach, chargeable: chargeable)
              end
            end
            nil
          end

          def setup_goal_within_budget?(origin, defender, slot, budget)
            setup_candidate_points(origin, defender, slot).any? do |point|
              Geometry::Battlefield.distance_between(origin, point) <= budget + 0.05
            end
          end

          # Side is legal only if a pad stays clear after the free face toward the target.
          def setup_side_landable?(origin, defender, slot, budget, obstacles)
            setup_candidate_points(origin, defender, slot).any? do |point|
              score_setup_landing(origin, defender, point, budget, obstacles)
            end
          end

          def build_approach_intent(combatant:, nearest:, obstacles:, enemies: [], contact_slot: nil, allow_ally_bypass: false, approach_mode: :flyer_charge, terrain: [], chargeable: true)
            return nil unless nearest
            return nil if Decisions::Movement.engaged?(combatant, nearest)

            budget = Decisions::Movement.budget_for(combatant, enemies: enemies)
            return nil if budget <= 0.05

            case approach_mode
            when :flyer_charge
              return nil unless chargeable

              build_charge_intent(combatant, nearest, obstacles, contact_slot, budget, approach_mode)
            when :flyer_approach
              build_closing_intent(combatant, nearest, obstacles, contact_slot, budget, approach_mode)
            else
              build_setup_intent(combatant, nearest, obstacles, contact_slot, budget, approach_mode)
            end
          end

          def build_charge_intent(combatant, nearest, obstacles, contact_slot, budget, approach_mode)
            slot = contact_slot.to_s
            slot = "front" if slot.empty?
            candidates = charge_landing_candidates(combatant, nearest, slot)
            best = nil

            candidates.each do |candidate|
              plan = plan_flyer_leap(
                origin: combatant,
                goal_point: candidate,
                facing: candidate[:facing],
                budget: budget,
                obstacles: obstacles,
                contact_id: nearest[:entity_id],
                face_target: nearest
              )
              next unless plan && plan[:pose]

              landed = combatant.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
              next unless Geometry::Battlefield.distance_between_units(landed, nearest) <= Decisions::Movement::ENGAGE + 0.05

              score = Geometry::Battlefield.distance_between_units(landed, nearest)
              if best.nil? || score < best[:score]
                best = { plan: plan, destination: plan[:pose], score: score }
              end
            end
            return nil unless best

            {
              kind: "approach",
              combatant: combatant,
              nearest: nearest,
              plan: best[:plan].merge(leap: true, charge: true, kind: "flyer_charge", heading: best[:destination][:facing]),
              budget: budget,
              destination: best[:destination],
              wait: false,
              contact_slot: contact_slot,
              approach_mode: approach_mode,
              charge_contact_id: nearest[:entity_id]
            }
          end

          def build_setup_intent(combatant, nearest, obstacles, contact_slot, budget, approach_mode)
            preferred = approach_mode == :flyer_setup_rear ? "rear" : "flank"
            preferred = contact_slot.to_s if %w[rear flank].include?(contact_slot.to_s)
            best = nil

            [ preferred, (%w[rear flank] - [ preferred ]).first ].compact.each do |slot|
              setup_candidate_points(combatant, nearest, slot).each do |point|
                landing = score_setup_landing(combatant, nearest, point, budget, obstacles)
                next unless landing

                prefer = slot == preferred ? 0 : 1
                score = [ prefer ] + landing[:score]
                next unless best.nil? || (score <=> best[:score]) < 0

                best = landing.merge(score: score, slot: slot)
              end
            end
            return nil unless best

            mode = best[:slot] == "rear" ? :flyer_setup_rear : :flyer_setup_flank
            {
              kind: "approach",
              combatant: combatant,
              nearest: nearest,
              plan: best[:plan].merge(leap: true, charge: false, kind: "flyer_leap", heading: best[:destination][:facing]),
              budget: budget,
              destination: best[:destination],
              wait: false,
              contact_slot: best[:slot],
              approach_mode: mode,
              charge_contact_id: nil
            }
          end

          def score_setup_landing(combatant, nearest, point, budget, obstacles)
            facing = Geometry::Battlefield.facing_into_contact_face(
              combatant.merge(x: point[:x], y: point[:y]),
              nearest
            )
            plan = plan_flyer_leap(
              origin: combatant,
              goal_point: point,
              facing: facing,
              budget: budget,
              obstacles: obstacles,
              contact_id: nil,
              face_target: nearest
            )
            return nil unless plan && plan[:pose]

            landed = combatant.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
            return nil if Geometry::Battlefield.distance_between_units(landed, nearest) < Decisions::Movement::CONTACT

            in_arc = Geometry::Battlefield.in_front_arc?(landed, nearest, landed[:facing]) ? 0 : 1
            geo = Geometry::Battlefield.classify_attack_vector(landed, nearest)
            geo_rank = geo == "rear" ? 0 : (geo == "flank" ? 1 : 2)
            travel = Geometry::Battlefield.distance_between(combatant, plan[:pose])
            { plan: plan, destination: plan[:pose], score: [ in_arc, geo_rank, -travel ] }
          end

          def build_closing_intent(combatant, nearest, obstacles, contact_slot, budget, approach_mode)
            slot = %w[rear flank].include?(contact_slot.to_s) ? contact_slot.to_s : "rear"
            goals = setup_candidate_points(combatant, nearest, slot)
            return nil if goals.empty?

            primary_goal = goals.min_by { |point| Geometry::Battlefield.distance_between(combatant, point) }
            threats = opposing_units(combatant, obstacles)
            threats = [ nearest ] if threats.empty?
            start_goal = Geometry::Battlefield.distance_between(combatant, primary_goal)
            start_enemy = Geometry::Battlefield.distance_between_units(combatant, nearest)
            best = nil

            closing_candidate_points(combatant, primary_goal, budget).each do |point|
              facing = Geometry::Battlefield.heading_to(
                combatant.merge(x: point[:x], y: point[:y]),
                nearest
              )
              plan = plan_flyer_leap(
                origin: combatant,
                goal_point: point,
                facing: facing,
                budget: budget,
                obstacles: obstacles,
                contact_id: nil,
                face_target: nearest
              )
              next unless plan && plan[:pose]

              landed = combatant.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
              next if threats.any? { |enemy| Geometry::Battlefield.distance_between_units(landed, enemy) < Decisions::Movement::CONTACT }

              goal_dist = Geometry::Battlefield.distance_between(landed, primary_goal)
              enemy_dist = Geometry::Battlefield.distance_between_units(landed, nearest)
              progress = [ start_goal - goal_dist, start_enemy - enemy_dist ].max
              next if progress < 0.2

              arc_hits = threats.count { |enemy| Geometry::Battlefield.in_front_arc?(enemy, landed, enemy[:facing]) }
              charge_danger = threats.count do |enemy|
                next false unless Decisions::Roles.melee_primary?(enemy)

                reach = enemy[:movement].to_f + Decisions::Movement::CONTACT
                Geometry::Battlefield.in_front_arc?(enemy, landed, enemy[:facing]) &&
                  Geometry::Battlefield.distance_between_units(landed, enemy) <= reach
              end
              geo = Geometry::Battlefield.classify_attack_vector(landed, nearest)
              geo_rank = geo == "rear" ? 0 : (geo == "flank" ? 1 : 2)
              faces_target = Geometry::Battlefield.in_front_arc?(landed, nearest, landed[:facing]) ? 0 : 1
              score = [ arc_hits, charge_danger, -progress, geo_rank, faces_target, enemy_dist ]
              if best.nil? || (score <=> best[:score]) < 0
                best = { plan: plan, destination: plan[:pose], score: score }
              end
            end
            return nil unless best

            {
              kind: "approach",
              combatant: combatant,
              nearest: nearest,
              plan: best[:plan].merge(leap: true, charge: false, kind: "flyer_leap", heading: best[:destination][:facing]),
              budget: budget,
              destination: best[:destination],
              wait: false,
              contact_slot: contact_slot,
              approach_mode: approach_mode,
              charge_contact_id: nil
            }
          end

          def closing_candidate_points(origin, goal, budget)
            heading = Geometry::Battlefield.heading_to(origin, goal)
            points = [ goal ]
            [ 0, 20, -20, 40, -40, 65, -65, 90, -90, 120, -120 ].each do |delta|
              dir = Geometry::Battlefield.normalize_facing(heading + delta)
              stepped = Geometry::Battlefield.move_along_facing(origin.merge(facing: dir), budget)
              points << Geometry::Battlefield.clamp_battlefield_position(stepped)
            end
            [ 0.45, 0.7 ].each do |frac|
              stepped = Geometry::Battlefield.move_along_facing(origin.merge(facing: heading), budget * frac)
              points << Geometry::Battlefield.clamp_battlefield_position(stepped)
            end
            points.uniq { |row| [ row[:x].round(2), row[:y].round(2) ] }
          end

          def opposing_units(combatant, obstacles)
            Pathing.active_units(obstacles).select do |entry|
              next false if entry[:entity_id] == combatant[:entity_id]

              if combatant[:side_key] && entry[:side_key]
                entry[:side_key].to_s != combatant[:side_key].to_s
              else
                entry[:side_index].to_i != combatant[:side_index].to_i
              end
            end
          end

          def charge_landing_candidates(origin, defender, slot)
            facings = []
            probes = []

            if %w[flank rear].include?(slot)
              Pathing.contact_slot_points(origin, defender, slot).each do |point|
                probe = origin.merge(x: point[:x], y: point[:y])
                facing = Geometry::Battlefield.facing_into_contact_face(probe, defender)
                probes << probe.merge(facing: facing)
                facings << facing
              end
            end

            facings << Geometry::Battlefield.facing_into_contact_face(origin, defender)
            facings << Geometry::Battlefield.heading_to(origin, defender)
            facings.uniq.each do |facing|
              dest = Geometry::Battlefield.charge_destination(origin, defender, facing)
              probes << origin.merge(x: dest[:x], y: dest[:y], facing: dest[:facing])
            end

            # Also try charge from slot probes so flank/rear landings aim correctly.
            Pathing.contact_slot_points(origin, defender, slot == "front" ? "flank" : slot).each do |point|
              probe = origin.merge(x: point[:x], y: point[:y])
              facing = Geometry::Battlefield.facing_into_contact_face(probe, defender)
              dest = Geometry::Battlefield.charge_destination(probe.merge(facing: facing), defender, facing)
              probes << origin.merge(x: dest[:x], y: dest[:y], facing: dest[:facing])
            end

            probes.uniq { |row| [ row[:x].round(3), row[:y].round(3), row[:facing].round(1) ] }
          end

          def setup_candidate_points(origin, defender, slot)
            points = Pathing.contact_slot_points(origin, defender, slot)
            return points if points.empty?

            # Push slightly farther out so setup never rests in the CONTACT band.
            dims = Geometry::Battlefield.unit_dimensions(defender)
            own = Geometry::Battlefield.unit_dimensions(origin)
            extra = SETUP_CLEARANCE
            forward = Geometry::Battlefield.facing_vector(defender[:facing])
            right = Geometry::Battlefield.right_vector(defender[:facing])

            expanded =
              case slot.to_s
              when "rear"
                depth = dims[:half_depth] + own[:half_depth] + Decisions::Movement::CONTACT + 0.35 + extra
                [
                  Geometry::Battlefield.clamp_battlefield_position(
                    x: defender[:x] - (forward[:x] * depth),
                    y: defender[:y] - (forward[:y] * depth),
                    facing: 0
                  )
                ]
              else
                clearance = dims[:half_width] + own[:half_width] + Decisions::Movement::CONTACT + 0.35 + extra
                [
                  Geometry::Battlefield.clamp_battlefield_position(
                    x: defender[:x] + (right[:x] * clearance),
                    y: defender[:y] + (right[:y] * clearance),
                    facing: 0
                  ),
                  Geometry::Battlefield.clamp_battlefield_position(
                    x: defender[:x] - (right[:x] * clearance),
                    y: defender[:y] - (right[:y] * clearance),
                    facing: 0
                  )
                ]
              end
            (points + expanded).uniq { |row| [ row[:x].round(3), row[:y].round(3) ] }
          end

          # Leap anywhere in the MV disk; path is not collision-tested. Final pose must be clear.
          def plan_flyer_leap(origin:, goal_point:, facing:, budget:, obstacles:, contact_id: nil, face_target: nil)
            return nil if budget.to_f <= 0.05

            desired_facing = Geometry::Battlefield.normalize_facing(facing)
            gx = goal_point[:x].to_f
            gy = goal_point[:y].to_f
            clamped = Geometry::Battlefield.clamp_battlefield_position(x: gx, y: gy, facing: desired_facing)
            dist = Geometry::Battlefield.distance_between(origin, clamped)

            pose =
              if dist <= budget + 0.05
                origin.merge(x: clamped[:x], y: clamped[:y], facing: desired_facing)
              else
                heading = Geometry::Battlefield.heading_to(origin, clamped)
                stepped = Geometry::Battlefield.move_along_facing(origin.merge(facing: heading), budget)
                origin.merge(x: stepped[:x], y: stepped[:y], facing: desired_facing)
              end

            pose = landing_facing_toward(pose, face_target) if face_target
            unless flyer_landing_clear?(pose, obstacles, contact_id: contact_id)
              pose = shorten_leap(origin, pose, obstacles, contact_id: contact_id)
            end
            return nil unless pose
            return nil unless flyer_landing_clear?(pose, obstacles, contact_id: contact_id)

            landing_facing = pose[:facing]

            meaningful =
              Geometry::Battlefield.distance_between(origin, pose) > 0.05 ||
              Geometry::Battlefield.shortest_facing_delta(origin[:facing], landing_facing).abs > 0.05
            return nil unless meaningful

            {
              pose: pose,
              desired: origin.merge(x: clamped[:x], y: clamped[:y], facing: desired_facing),
              truncated: Geometry::Battlefield.distance_between(pose, clamped) > 0.05,
              avoided: false,
              blocked_by_ally: false,
              blocker: nil,
              leap: true,
              wheel: nil,
              heading: landing_facing
            }
          end

          def landing_facing_toward(pose, target)
            pose.merge(facing: Geometry::Battlefield.heading_to(pose, target))
          end

          def flyer_landing_clear?(pose, obstacles, contact_id: nil)
            Pathing.first_blocker(pose, obstacles, contact_id: contact_id, origin: pose).nil?
          end

          def shorten_leap(origin, desired, obstacles, contact_id: nil)
            best = nil
            12.times do |index|
              t = 1.0 - ((index + 1) / 12.0)
              pose = origin.merge(
                x: origin[:x].to_f + ((desired[:x].to_f - origin[:x].to_f) * t),
                y: origin[:y].to_f + ((desired[:y].to_f - origin[:y].to_f) * t),
                facing: desired[:facing]
              )
              next unless flyer_landing_clear?(pose, obstacles, contact_id: contact_id)

              best = pose
              break
            end
            best
          end

          def corner_contact_reachable?(origin, defender, budget, terrain: [])
            plan = plan_flyer_leap(
              origin: origin,
              goal_point: defender,
              facing: Geometry::Battlefield.heading_to(origin, defender),
              budget: budget.to_f,
              obstacles: [ defender ],
              contact_id: defender[:entity_id],
              face_target: defender
            )
            pose = plan && plan[:pose]
            return false unless pose

            landed = origin.merge(x: pose[:x], y: pose[:y], facing: pose[:facing])
            Geometry::Battlefield.distance_between_units(landed, defender) <= Decisions::Movement::ENGAGE
          end
        end
      end
    end
  end
end
