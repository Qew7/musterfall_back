module Sim
  module Battle
    module Phases
      module AttackResolution
        CONTACT = Geometry::Battlefield::CONFIG[:melee_contact_tolerance]

        module_function

        def create_phase(type, label)
          { type: type, label: label, events: [], actions: [], snapshot: nil, allow_routing_melee: false }
        end

        def add_event(phase, event)
          phase[:events] << event
        end

        def resolve!(phase:, acting_side:, target_side:, round_number:, attack_type:, rng:)
          all_combatants = acting_side[:combatants] + target_side[:combatants]
          attackers = acting_side[:combatants]
            .select { |entry| entry[:current_health].to_i > 0 }
            .select { |entry| can_attack?(entry, attack_type, allow_routing_melee: phase[:allow_routing_melee]) }
            .sort_by { |entry| -entry[:initiative].to_i }

          if attackers.empty?
            add_event(phase, "Подходящих атакующих нет.")
            phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
            return phase
          end

          attackers.each do |attacker|
            selection = choose_target(attacker, target_side[:combatants], attack_type, all_combatants)
            next unless selection

            target = selection[:target]
            vector = selection[:vector]
            blockers = attacker[:requires_line_of_sight] ? Geometry::Battlefield.line_of_sight_blockers(attacker, target, all_combatants) : []
            victims = attack_type == "melee" ? [ { target: target, multiplier: 1 } ] : Geometry::Battlefield.attack_victims(attacker, target, target_side[:combatants], attack_type)
            entries = attack_type == "melee" ? melee_entries(attacker, target, vector, round_number) : [
              {
                actor_id: attacker[:entity_id],
                actor_unit_id: attacker[:entity_id],
                actor_name: attacker[:name],
                actor_role: attacker[:kind] == "hero" ? "hero" : "unit",
                profile: attacker,
                damage: damage(attacker, target, attack_type, vector, round_number)
              }
            ]

            entries.each do |entry|
              next if target[:current_health].to_i <= 0 || entry[:damage].to_i <= 0

              attacks = entry.dig(:profile, :attacks) || attacker[:attacks] || 1
              attacks.times do
                attacker_for_skill = attack_type == "melee" ? entry[:profile] : attacker
                unless hit?(attacker_for_skill, target, attack_type, rng)
                  add_event(phase, "#{format_actor(entry[:actor_role], entry[:actor_name])} промахивается по #{target[:name]}")
                  next
                end

                actor_state = State.snapshot_combatant(attacker)
                before = State.snapshot_combatant(target)
                target[:current_health] = [ 0, target[:current_health] - entry[:damage] ].max
                State.sync_combatant_footprint!(target)
                after = State.snapshot_combatant(target)

                if attack_type == "melee"
                  distribute_contributor_experience!(entry[:profile], entry[:damage])
                else
                  distribute_experience!(attacker, attack_type, entry[:damage])
                end

                add_event(phase, "#{format_actor(entry[:actor_role], entry[:actor_name])} наносит #{entry[:damage]} урона по #{target[:name]} (#{vector})")
                action = {
                  type: attack_type,
                  actor_id: entry[:actor_id],
                  actor_unit_id: entry[:actor_unit_id],
                  actor_name: entry[:actor_name],
                  actor_role: entry[:actor_role],
                  target_id: target[:entity_id],
                  target_name: target[:name],
                  vector: vector,
                  damage: entry[:damage],
                  blockers: blockers.map { |blocker| blocker[:entity_id] },
                  requires_line_of_sight: attacker[:requires_line_of_sight],
                  template: attack_type == "melee" ? nil : template_descriptor(attacker, target, victims, attack_type),
                  affected_ids: victims.map { |victim| victim[:target][:entity_id] },
                  actor_state: actor_state,
                  target_state_before: before,
                  target_state_after: after,
                  charge: melee_charge(attacker, target, attack_type, vector),
                  snapshot: State.snapshot_battlefield([ acting_side, target_side ])
                }
                action[:summary] = summarize(action, phase[:type])
                action[:details] = details(action)
                phase[:actions] << action
              end
            end
          end

          add_event(phase, "Эта фаза прошла без результата.") if phase[:events].empty?
          phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          phase
        end

        def damage(attacker, defender, attack_type, vector, round_number)
          base = base_power(attacker, attack_type)
          return 0 if base <= 0

          abilities = Array(attacker[:abilities])
          weapon_type = attack_type == "magic" ? "magic" : attacker[:weapon_type]
          armor_factor = Constants::WEAPON_VS_ARMOR.dig(defender[:armor_type], weapon_type) || 1
          facing_factor = if Array(defender[:abilities]).include?("skirmisher")
            1
          elsif vector == "rear"
            1.55
          elsif vector == "flank"
            1.25
          else
            1
          end
          phase_factor = attack_type == "shooting" ? 0.9 : 1
          charge_factor = abilities.include?("charge") && round_number == 1 && attack_type == "melee" ? 1.3 : 1
          steady_factor = Array(defender[:abilities]).include?("steadfast") && vector == "front" ? 0.85 : 1
          ferocious_factor = abilities.include?("ferocious") && attack_type == "melee" ? 1.1 : 1
          machine_factor = abilities.include?("machine") && attack_type == "shooting" ? 1.25 : 1
          raw = base * armor_factor * facing_factor * phase_factor * charge_factor * steady_factor * ferocious_factor * machine_factor
          [ 1, (raw / 2.2).round ].max
        end

        def hit_chance(attacker, defender, attack_type)
          case attack_type
          when "melee"
            attacker_skill = attacker[:skill] || 3
            defender_skill = defender[:skill] || 3
            return 5 / 6.0 if attacker_skill > defender_skill
            return 3 / 6.0 if attacker_skill < defender_skill

            4 / 6.0
          when "shooting"
            (attacker[:skill] || 3) / 7.0
          else
            1.0
          end
        end

        def hit?(attacker, defender, attack_type, rng)
          rng.rand < hit_chance(attacker, defender, attack_type)
        end

        def can_attack?(attacker, attack_type, allow_routing_melee: false)
          return false if attacker[:is_routing] && !(allow_routing_melee && attack_type == "melee")

          case attack_type
          when "magic" then attacker[:spell].to_i > 0
          when "shooting" then attacker[:ranged].to_i > 0
          else attacker[:melee].to_i > 0
          end
        end

        def choose_target(attacker, enemies, attack_type, all_combatants)
          living = enemies.select { |entry| entry[:current_health].to_i > 0 }
          return nil if living.empty?

          if attack_type == "melee"
            engaged = living
              .map { |target| { target: target, distance: Geometry::Battlefield.distance_between_units(attacker, target), vector: Geometry::Battlefield.classify_attack_vector(attacker, target) } }
              .select { |entry| entry[:distance] <= CONTACT }
              .sort_by { |entry| [ entry[:distance], vector_priority(entry[:vector]) ] }
            return nil if engaged.empty?

            return { target: engaged.first[:target], vector: engaged.first[:vector] }
          end

          available = if attack_type == "shooting"
            living.select { |target| can_target_ranged?(attacker, target, all_combatants) }
          else
            living
          end
          return nil if available.empty?

          prioritized = prioritize_routing(available)
          same_lane = Constants::BATTLE_ROWS.flat_map { |row| prioritized.select { |entry| entry[:lane] == attacker[:lane] && entry[:row] == row } }
          if same_lane.any?
            target = same_lane.first
            return { target: target, vector: target[:row] == "front" ? "front" : "rear" }
          end

          adjacent = Constants::LANE_ORDER.reject { |lane| lane == attacker[:lane] }.flat_map do |lane|
            Constants::BATTLE_ROWS.flat_map { |row| prioritized.select { |entry| entry[:lane] == lane && entry[:row] == row } }
          end
          return { target: adjacent.first, vector: "flank" } if adjacent.any?

          { target: prioritized.first, vector: "front" }
        end

        def can_target_ranged?(attacker, target, all_combatants)
          return false if !Array(attacker[:abilities]).include?("skirmisher") && !Geometry::Battlefield.in_front_arc?(attacker, target, attacker[:facing])
          return false if melee_contact?(target, all_combatants)

          Geometry::Battlefield.line_of_sight_blockers(attacker, target, all_combatants).empty?
        end

        def melee_contact?(unit, all_combatants)
          all_combatants.any? do |entry|
            entry[:entity_id] != unit[:entity_id] &&
              entry[:current_health].to_i > 0 &&
              Geometry::Battlefield.distance_between_units(unit, entry) <= CONTACT
          end
        end

        def melee_entries(attacker, defender, vector, round_number)
          engaged = engaged_model_count(attacker, defender)
          return [] if engaged <= 0

          contact_side = detailed_contact_side(attacker, defender)
          primary, *attached = attacker[:contributors][:melee]
          entries = []
          if primary
            profile = primary.merge(melee: primary[:power] * engaged, attacks: attacker[:attacks])
            entries << {
              actor_id: primary[:entity_id],
              actor_unit_id: attacker[:entity_id],
              actor_name: primary[:kind] == "unit" && engaged > 1 ? "#{attacker[:name]} (#{engaged} моделей)" : primary[:name],
              actor_role: primary[:kind] == "hero" ? "hero" : "unit",
              profile: profile,
              damage: damage(profile, defender, "melee", vector, round_number)
            }
          end

          attached.select { |contributor| contributor[:kind] == "hero" }
            .select { |contributor| hero_eligible?(contributor, contact_side) }
            .each do |contributor|
              profile = contributor.merge(melee: contributor[:power])
              entries << {
                actor_id: contributor[:entity_id],
                actor_unit_id: attacker[:entity_id],
                actor_name: contributor[:name],
                actor_role: "hero",
                profile: profile,
                damage: damage(profile, defender, "melee", vector, round_number)
              }
            end
          entries
        end

        def engaged_model_count(attacker, defender)
          contact_side = detailed_contact_side(attacker, defender)
          capacity = side_model_capacity(attacker, contact_side)
          return 0 if capacity <= 0

          span = contact_span(attacker, defender, contact_side)
          model_span = model_span(attacker, contact_side)
          return [ 1, capacity ].max if model_span <= 0

          engaged = ((span + CONTACT) / model_span).ceil
          [ [ engaged, capacity ].min, 1 ].max
        end

        def side_model_capacity(unit, contact_side)
          return unit[:current_health].to_i > 0 ? 1 : 0 if unit[:kind] == "hero"
          return [ unit[:ranks].to_i, 0 ].max if %w[left right].include?(contact_side)

          [ unit[:files].to_i, 0 ].max
        end

        def model_span(unit, contact_side)
          %w[left right].include?(contact_side) ? [ unit[:model_depth].to_f, 0 ].max : [ unit[:model_width].to_f, 0 ].max
        end

        def contact_span(attacker, defender, contact_side)
          axis = %w[left right].include?(contact_side) ? Geometry::Battlefield.facing_vector(attacker[:facing]) : Geometry::Battlefield.right_vector(attacker[:facing])
          left = Geometry::Battlefield.project_unit_onto_axis(attacker, axis)
          right = Geometry::Battlefield.project_unit_onto_axis(defender, axis)
          [ 0, [ left[:max], right[:max] ].min - [ left[:min], right[:min] ].max ].max
        end

        def detailed_contact_side(unit, opponent)
          local = Geometry::Battlefield.point_in_local_unit_space(opponent, unit)
          if local[:longitudinal].abs >= local[:lateral].abs
            local[:longitudinal] >= 0 ? "front" : "rear"
          else
            local[:lateral] >= 0 ? "right" : "left"
          end
        end

        def hero_eligible?(contributor, contact_side)
          contributor[:attached_slot].nil? || contributor[:attached_slot] == contact_side
        end

        def base_power(attacker, attack_type)
          case attack_type
          when "magic" then attacker[:spell].to_i
          when "shooting" then attacker[:ranged].to_i
          else attacker[:melee].to_i
          end
        end

        def distribute_contributor_experience!(contributor, damage)
          return unless contributor[:kind] == "hero"

          contributor[:experience_gain] += [ 1, damage ].max
        end

        def distribute_experience!(attacker, attack_type, damage)
          contributors = attacker[:contributors][attack_type == "melee" ? :melee : :ranged] || []
          total = contributors.sum { |entry| entry[:power].to_i }
          contributors.each do |entry|
            next unless entry[:kind] == "hero"

            ratio = total.positive? ? entry[:power].to_f / total : 0
            entry[:experience_gain] += [ 1, (damage * ratio).round ].max
          end
        end

        def vector_priority(vector)
          { "rear" => 0, "flank" => 1 }.fetch(vector, 2)
        end

        def prioritize_routing(targets)
          targets.sort_by { |entry| entry[:is_routing] ? 0 : 1 }
        end

        def melee_charge(attacker, target, attack_type, vector)
          return nil unless attack_type == "melee"
          return nil unless Geometry::Battlefield.distance_between_units(attacker, target) > CONTACT

          {
            start: { x: attacker[:x], y: attacker[:y], facing: attacker[:facing] },
            destination: Geometry::Battlefield.charge_destination(attacker, target, Geometry::Battlefield.heading_to(attacker, target)),
            contact_point: Geometry::Battlefield.closest_point_on_unit(attacker, target),
            vector: vector
          }
        end

        def template_descriptor(attacker, target, victims, attack_type)
          kind = attack_type == "magic" ? attacker[:spell_template] : attacker[:shooting_template]
          affected = victims.map { |entry| entry[:target][:entity_id] }
          case kind
          when "blast", "volley"
            {
              shape: "circle",
              radius: kind == "blast" ? Geometry::Battlefield::CONFIG[:blast_radius] : Geometry::Battlefield::CONFIG[:volley_radius],
              center: { x: target[:x], y: target[:y] },
              kind: kind,
              affected_ids: affected
            }
          when "breath"
            {
              shape: "cone",
              radius: [ attacker[:shooting_range], attacker[:spell_range], 2.4 ].max,
              facing: attacker[:facing],
              origin: { x: attacker[:x], y: attacker[:y] },
              kind: kind,
              affected_ids: affected
            }
          else
            {
              shape: "line",
              start: { x: attacker[:x], y: attacker[:y] },
              end: { x: target[:x], y: target[:y] },
              kind: kind,
              affected_ids: affected
            }
          end
        end

        def summarize(action, phase_type)
          actor = format_actor(action[:actor_role], action[:actor_name])
          case phase_type
          when "melee" then "#{actor} атакует #{action[:target_name]} в #{describe_vector(action[:vector])} и наносит #{action[:damage]} урона."
          when "shooting" then "#{actor} стреляет по #{action[:target_name]} и наносит #{action[:damage]} урона."
          else "#{actor} применяет магию по #{action[:target_name]} и наносит #{action[:damage]} урона."
          end
        end

        def details(action)
          [
            "Атакующий до удара: #{format_state(action[:actor_state])}",
            "Цель до удара: #{format_state(action[:target_state_before])}",
            "Урон: #{action[:damage]}, направление: #{describe_vector(action[:vector])}, затронуто целей: #{Array(action[:affected_ids]).length}",
            "Цель после удара: #{format_state(action[:target_state_after])}"
          ].tap do |list|
            list << "Помехи по линии атаки: #{Array(action[:blockers]).join(', ')}" if Array(action[:blockers]).any?
          end
        end

        def format_state(state)
          return "нет данных" unless state

          "#{state[:name]} HP #{state[:current_health]}/#{state[:max_health]}, моделей #{state[:models_remaining]}, строй #{state[:row]}/#{state[:lane]}, ряды #{state[:ranks]}, файлы #{state[:files]}"
        end

        def describe_vector(vector)
          { "rear" => "тыл", "flank" => "фланг" }.fetch(vector, "фронт")
        end

        def format_actor(role, name)
          role == "hero" ? "Герой #{name}" : "Отряд #{name}"
        end
      end
    end
  end
end
