module Sim
  module Battle
    module Phases
      module Morale
        module_function

        def play_start(acting_side:, target_side:, round_number:, **)
          phase = AttackResolution.create_phase("start", "Фаза начала")
          routed = acting_side[:combatants].select { |combatant| combatant[:current_health].to_i > 0 && combatant[:is_routing] }
          if routed.empty?
            AttackResolution.add_event(phase, "Бегущих отрядов нет.")
            phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
            return phase
          end

          routed.each_with_index do |combatant, sequence|
            action = resolve_action(
              combatant: combatant,
              allies: acting_side[:combatants],
              enemies: target_side[:combatants],
              round_number: round_number,
              phase_type: "start",
              combat_score_delta: 0,
              sequence: sequence,
              engaged_enemies: []
            )
            action[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
            phase[:actions] << action
            AttackResolution.add_event(phase, action[:summary])
          end
          phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          phase
        end

        def resolve_post_melee!(phase:, acting_side:, target_side:, round_number:)
          engagements = melee_engagements(acting_side, target_side)
          engagements.each_with_index do |engagement, engagement_index|
            score = score_engagement(phase[:actions], engagement)
            if score[:left] <= score[:right]
              resolve_losing_side!(
                phase: phase,
                loser_side: acting_side,
                loser_combatants: engagement[:left],
                winner_combatants: engagement[:right],
                battle_sides: [ acting_side, target_side ],
                round_number: round_number,
                engagement_index: engagement_index,
                combat_score_delta: score[:right] - score[:left]
              )
            end
            if score[:right] <= score[:left]
              resolve_losing_side!(
                phase: phase,
                loser_side: target_side,
                loser_combatants: engagement[:right],
                winner_combatants: engagement[:left],
                battle_sides: [ acting_side, target_side ],
                round_number: round_number,
                engagement_index: engagement_index,
                combat_score_delta: score[:left] - score[:right]
              )
            end
          end
          phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          phase
        end

        def resolve_post_missile!(phase:, acting_side:, target_side:, round_number:, attack_type:)
          turn_key = "#{round_number}:#{acting_side[:player_id]}"
          collect_casualty_triggers(phase[:actions], attack_type, target_side[:combatants]).each_with_index do |entry, index|
            combatant = entry[:combatant]
            next if combatant[:current_health].to_i <= 0 || combatant[:is_routing]
            next if combatant[:last_missile_morale_turn_key] == turn_key

            action = resolve_action(
              combatant: combatant,
              allies: target_side[:combatants],
              enemies: acting_side[:combatants],
              round_number: round_number,
              phase_type: attack_type,
              combat_score_delta: 0,
              sequence: index,
              engaged_enemies: [],
              trigger: entry.slice(:reason, :phase_damage, :lost_models, :phase_start_models, :threshold_models).merge(starting_models: combatant[:starting_models])
            )
            combatant[:last_missile_morale_turn_key] = turn_key
            action[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
            phase[:actions] << action
            AttackResolution.add_event(phase, action[:summary])
          end
          phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          phase
        end

        def resolve_losing_side!(phase:, loser_side:, loser_combatants:, winner_combatants:, battle_sides:, round_number:, engagement_index:, combat_score_delta:)
          return if combat_score_delta <= 0

          loser_combatants.select { |combatant| combatant[:current_health].to_i > 0 }.each_with_index do |combatant, combatant_index|
            action = resolve_action(
              combatant: combatant,
              allies: loser_side[:combatants],
              enemies: winner_combatants,
              round_number: round_number,
              phase_type: "melee",
              combat_score_delta: combat_score_delta,
              sequence: (engagement_index * 10) + combatant_index,
              engaged_enemies: winner_combatants
            )
            action[:snapshot] = State.snapshot_battlefield(battle_sides)
            phase[:actions] << action
            AttackResolution.add_event(phase, action[:summary])
          end
        end

        def resolve_action(combatant:, allies:, enemies:, round_number:, phase_type:, combat_score_delta:, sequence:, engaged_enemies: [], trigger: nil)
          before = State.snapshot_combatant(combatant)
          from = position_of(combatant)
          check = resolve_check(combatant: combatant, allies: allies, enemies: enemies, round_number: round_number, phase_type: phase_type, combat_score_delta: combat_score_delta, sequence: sequence)
          damage = 0
          to = nil
          retreat = {}
          retreat_edge = nil
          escaped = false
          about_faced = false

          if check[:passed]
            if combatant[:is_routing]
              # Keep flee facing — free about-face is only when breaking, not on rally.
              combatant[:is_routing] = false
              State.sync_combatant_footprint!(combatant)
              to = position_of(combatant)
              summary = "#{combatant[:name]} собирается с духом и перестаёт бежать."
            else
              summary = "#{combatant[:name]} выдерживает проверку морали."
            end
          elsif Array(combatant[:abilities]).include?("undead")
            damage = check[:failure_margin]
            combatant[:current_health] = [ 0, combatant[:current_health] - damage ].max
            State.sync_combatant_footprint!(combatant)
            summary = "#{combatant[:name]} проваливает проверку морали и теряет #{damage} здоровья вместо бегства."
          else
            newly_routing = !combatant[:is_routing]
            combatant[:is_routing] = true
            if newly_routing
              flee_facing = flee_facing_for(combatant, engaged_enemies, enemies)
              if flee_facing
                combatant[:facing] = flee_facing
                about_faced = true
              end
            end
            blockers = (Array(allies) + Array(enemies)).reject { |entry| entry[:entity_id] == combatant[:entity_id] }
            retreat = retreat_toward_edge(
              combatant,
              combatant[:movement],
              obstacles: blockers,
              ally_ids: Array(allies).map { |entry| entry[:entity_id] }
            )
            combatant[:x] = retreat[:destination][:x]
            combatant[:y] = retreat[:destination][:y]
            retreat_edge = retreat[:edge]
            escaped = retreat[:escaped]
            if escaped
              combatant[:current_health] = 0
              combatant[:is_routing] = false
            end
            State.sync_combatant_footprint!(combatant)
            to = position_of(combatant)
            avoid_note = if retreat[:blocked_by_ally] && retreat[:blocker]
              " (путь закрыт союзником #{retreat[:blocker][:name]})"
            elsif retreat[:avoided]
              blocker_name = retreat.dig(:blocker, :name)
              blocker_name ? " (обходит #{blocker_name})" : " (обходит препятствие)"
            else
              ""
            end
            summary = if escaped
              "#{combatant[:name]} в панике покидает поле боя."
            elsif phase_type == "start"
              "#{combatant[:name]} продолжает бегство#{avoid_note}."
            elsif about_faced
              "#{combatant[:name]} ломает строй и бежит от угрозы#{avoid_note}."
            else
              "#{combatant[:name]} ломает строй и обращается в бегство#{avoid_note}."
            end
          end

          after = State.snapshot_combatant(combatant)
          {
            type: "morale",
            actor_id: combatant[:entity_id],
            actor_unit_id: combatant[:entity_id],
            actor_name: combatant[:name],
            actor_role: combatant[:kind] == "hero" ? "hero" : "unit",
            damage: damage,
            from: from,
            to: to,
            actor_state_before: before,
            actor_state_after: after,
            summary: summary,
            details: build_morale_details(
              combatant: combatant,
              before: before,
              after: after,
              check: check,
              combat_score_delta: combat_score_delta,
              phase_type: phase_type,
              about_faced: about_faced,
              retreat: retreat,
              retreat_edge: retreat_edge,
              escaped: escaped,
              damage: damage,
              from: from,
              to: to,
              trigger: trigger
            ),
            morale_check: {
              source_phase: phase_type,
              trigger: trigger&.dig(:reason) || (phase_type == "melee" ? "combat_score" : phase_type == "start" ? "rally" : "phase_casualties"),
              effective_morale: check[:effective_morale],
              morale_source: check[:source],
              threshold: check[:threshold],
              roll: check[:roll],
              passed: check[:passed],
              failure_margin: check[:failure_margin],
              combat_score_delta: combat_score_delta,
              phase_damage: trigger&.dig(:phase_damage) || 0,
              lost_models: trigger&.dig(:lost_models) || 0,
              starting_models: trigger&.dig(:starting_models) || combatant[:starting_models],
              phase_start_models: trigger&.dig(:phase_start_models) || 0,
              threshold_models: trigger&.dig(:threshold_models) || 0,
              status_before: before[:is_routing],
              status_after: after[:is_routing],
              damage_applied: damage,
              retreat_edge: retreat_edge,
              escaped: escaped
            },
            snapshot: nil
          }
        end

        def build_morale_details(combatant:, before:, after:, check:, combat_score_delta:, phase_type:, about_faced:, retreat:, retreat_edge:, escaped:, damage:, from:, to:, trigger:)
          lines = [
            "actor=#{combatant[:entity_id]} #{combatant[:name]} phase=#{phase_type}",
            "morale roll=#{check[:roll]} threshold=#{check[:threshold]} passed=#{check[:passed]} failure_margin=#{check[:failure_margin]}",
            "effective_morale=#{check[:effective_morale]} source=#{check[:source]} combat_score_delta=#{combat_score_delta}",
            "routing #{before[:is_routing]} → #{after[:is_routing]}; about_faced=#{about_faced}; free_about_face_only_on_break=true"
          ]
          if about_faced
            lines << "flee_facing=#{format("%.1f", combatant[:facing].to_f)}° (бесплатный разворот только при старте бегства)"
          end
          if from && to
            lines << "from=(#{format("%.1f", from[:x].to_f)}, #{format("%.1f", from[:y].to_f)}) f#{format("%.1f", from[:facing].to_f)}°"
            lines << "to=(#{format("%.1f", to[:x].to_f)}, #{format("%.1f", to[:y].to_f)}) f#{format("%.1f", to[:facing].to_f)}°"
          elsif from
            lines << "pose=(#{format("%.1f", from[:x].to_f)}, #{format("%.1f", from[:y].to_f)}) f#{format("%.1f", from[:facing].to_f)}°"
          end
          if retreat.is_a?(Hash) && retreat[:destination]
            lines << "retreat edge=#{retreat_edge || "-"} avoided=#{retreat[:avoided]} blocked_by_ally=#{retreat[:blocked_by_ally]} escaped=#{escaped}"
            dest = retreat[:destination]
            lines << "retreat pose=(#{format("%.1f", dest[:x].to_f)}, #{format("%.1f", dest[:y].to_f)}) f#{format("%.1f", dest[:facing].to_f)}°"
            if retreat[:blocker]
              lines << "retreat blocker=#{retreat[:blocker][:name]}(#{retreat[:blocker][:entity_id]})"
            end
          end
          lines << "undead_damage=#{damage}" if damage.positive?
          if trigger
            lines << "trigger=#{trigger[:reason]} phase_damage=#{trigger[:phase_damage]} lost_models=#{trigger[:lost_models]}"
          end
          lines
        end

        def resolve_check(combatant:, allies:, enemies:, round_number:, phase_type:, combat_score_delta:, sequence:)
          source = effective_morale(combatant, allies)
          fear = enemies.any? { |enemy| Array(enemy[:abilities]).include?("fear") } ? 1 : 0
          discipline = Array(combatant[:abilities]).include?("disciplined") ? 1 : 0
          threshold = [ 2, source[:value] + discipline - combat_score_delta - fear ].max
          roll = roll_dice("#{phase_type}:#{round_number}:#{sequence}:#{combatant[:entity_id]}")
          {
            effective_morale: source[:value],
            source: source[:label],
            threshold: threshold,
            roll: roll,
            passed: roll <= threshold,
            failure_margin: [ 0, roll - threshold ].max
          }
        end

        def effective_morale(combatant, allies)
          return { value: combatant[:morale], label: combatant[:name] } if combatant[:kind] == "hero"

          sources = muster_sources(allies)
            .select { |source| source[:morale] > combatant[:morale] }
            .select { |source| Geometry::Battlefield.distance_between(combatant, source) <= source[:morale] }
            .sort_by { |source| [ -source[:morale], Geometry::Battlefield.distance_between(combatant, source) ] }
          return { value: combatant[:morale], label: combatant[:name] } if sources.empty?

          { value: sources.first[:morale], label: "Muster от #{sources.first[:name]}" }
        end

        def muster_sources(allies)
          sources = []
          allies.each do |combatant|
            if combatant[:kind] == "hero" && Array(combatant[:abilities]).include?("muster")
              sources << { entity_id: combatant[:entity_id], name: combatant[:name], morale: combatant[:morale], x: combatant[:x], y: combatant[:y] }
            end
            Array(combatant[:attached_heroes]).each do |hero|
              next unless Array(hero[:abilities]).include?("muster")

              sources << { entity_id: hero[:entity_id], name: hero[:name], morale: hero[:morale], x: combatant[:x], y: combatant[:y] }
            end
          end
          sources
        end

        def melee_engagements(acting_side, target_side)
          living = (acting_side[:combatants] + target_side[:combatants]).select { |combatant| combatant[:current_health].to_i > 0 }
          visited = {}
          engagements = []
          living.each do |combatant|
            next if visited[combatant[:entity_id]]

            queue = [ combatant ]
            cluster = []
            while queue.any?
              current = queue.shift
              next if current.nil? || visited[current[:entity_id]]

              visited[current[:entity_id]] = true
              cluster << current
              living.each do |candidate|
                next if visited[candidate[:entity_id]] || candidate[:side_key] == current[:side_key]
                next unless Geometry::Battlefield.distance_between_units(current, candidate) <= Geometry::Battlefield::CONFIG[:melee_contact_tolerance]

                queue << candidate
              end
            end
            left = cluster.select { |entry| entry[:side_key] == acting_side[:side_key] }
            right = cluster.select { |entry| entry[:side_key] == target_side[:side_key] }
            engagements << { left: left, right: right } if left.any? && right.any?
          end
          engagements
        end

        def score_engagement(actions, engagement)
          left_ids = engagement[:left].map { |combatant| combatant[:entity_id] }
          right_ids = engagement[:right].map { |combatant| combatant[:entity_id] }
          actions.select { |action| action[:type] == "melee" }.each_with_object(left: 0, right: 0) do |action, score|
            score[:left] += action[:damage].to_i if left_ids.include?(action[:actor_unit_id]) && right_ids.include?(action[:target_id])
            score[:right] += action[:damage].to_i if right_ids.include?(action[:actor_unit_id]) && left_ids.include?(action[:target_id])
          end
        end

        def roll_dice(seed)
          hash = 0
          seed.each_byte { |byte| hash = (((hash << 5) - hash) + byte) & 0xFFFFFFFF }
          normalized = hash.abs
          die_a = 1 + (normalized % 6)
          die_b = 1 + ((normalized / 7) % 6)
          die_a + die_b
        end

        # Face directly away from the threat that caused the break (not a blind +180 from current facing).
        def flee_facing_for(combatant, engaged_enemies, enemies)
          threats = Array(engaged_enemies).select { |enemy| enemy[:current_health].nil? || enemy[:current_health].to_i > 0 }
          threats = Array(enemies).select { |enemy| enemy[:current_health].to_i > 0 } if threats.empty?
          return nil if threats.empty?

          heading_away(combatant, threats)
        end

        def heading_away(combatant, enemies)
          center = enemies.each_with_object(x: 0.0, y: 0.0) do |enemy, memo|
            memo[:x] += enemy[:x].to_f
            memo[:y] += enemy[:y].to_f
          end
          average = { x: center[:x] / enemies.length, y: center[:y] / enemies.length }
          Geometry::Battlefield.heading_to(average, combatant)
        end

        def retreat_toward_edge(combatant, distance, obstacles: [], ally_ids: nil)
          plan = Pathing.plan_retreat(
            origin: combatant,
            distance: distance,
            obstacles: obstacles,
            ally_ids: ally_ids
          )
          destination = plan[:pose] || { x: combatant[:x], y: combatant[:y], facing: combatant[:facing] }
          {
            edge: plan[:edge],
            destination: destination,
            facing: destination[:facing],
            escaped: outside?(destination),
            avoided: plan[:avoided],
            blocked_by_ally: !!plan[:blocked_by_ally],
            blocker: plan[:blocker]
          }
        end

        def outside?(position)
          position[:x] < 0 || position[:y] < 0 || position[:x] > Geometry::Battlefield::CONFIG[:width] - 1 || position[:y] > Geometry::Battlefield::CONFIG[:height] - 1
        end

        def nearest_edge(combatant)
          Pathing.ordered_edges(combatant).first
        end

        def nearest_enemy(combatant, enemies)
          enemies.select { |enemy| enemy[:current_health].to_i > 0 }
            .min_by { |enemy| [ enemy[:is_routing] ? 0 : 1, Geometry::Battlefield.distance_between(combatant, enemy) ] }
        end

        def collect_casualty_triggers(actions, attack_type, combatants)
          by_id = combatants.index_by { |combatant| combatant[:entity_id] }
          casualties = {}
          actions.select { |action| action[:type] == attack_type }.each do |action|
            next unless action[:target_id] && action[:target_state_before] && action[:target_state_after]

            current = casualties[action[:target_id]] || { first_before: action[:target_state_before], last_after: action[:target_state_after], phase_damage: 0 }
            current[:phase_damage] += action[:damage].to_i
            current[:last_after] = action[:target_state_after]
            casualties[action[:target_id]] = current
          end

          casualties.filter_map do |target_id, entry|
            combatant = by_id[target_id]
            next unless combatant

            phase_start = entry[:first_before][:models_remaining] || combatant[:models_remaining] || 0
            remaining = entry[:last_after][:models_remaining] || combatant[:models_remaining] || 0
            lost = [ 0, phase_start - remaining ].max
            battle_threshold = combatant[:starting_models] * 0.25
            phase_threshold = phase_start * 0.25
            critical = remaining <= battle_threshold
            phase_loss = lost >= phase_threshold
            next unless critical || phase_loss

            reason = if critical && phase_loss
              "battle_and_phase_casualties"
            elsif critical
              "battle_remaining_critical"
            else
              "phase_casualties"
            end
            {
              combatant: combatant,
              phase_damage: entry[:phase_damage],
              lost_models: lost,
              phase_start_models: phase_start,
              threshold_models: critical ? battle_threshold : phase_threshold,
              reason: reason
            }
          end
        end

        def position_of(combatant)
          { x: combatant[:x], y: combatant[:y], facing: combatant[:facing], row: combatant[:row], lane: combatant[:lane] }
        end
      end
    end
  end
end
