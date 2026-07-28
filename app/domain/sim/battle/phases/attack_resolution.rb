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

        def resolve!(phase:, acting_side:, target_side:, round_number:, attack_type:, rng:, terrain: [])
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
            unless Rules.for(:melee).allow_attack?(attacker)
              note = attacker[:fear_check_note] || "rule"
              add_event(phase, "#{attacker[:name]} не атакует в этом раунде (#{note}).")
              next
            end

            selection = Decisions::Targeting.choose_target(
              attacker, target_side[:combatants], attack_type, all_combatants, terrain: terrain
            )
            next unless selection

            target = selection[:target]
            vector = selection[:vector]
            resolve_melee_strike!(
              phase: phase,
              attacker: attacker,
              target: target,
              vector: vector,
              acting_side: acting_side,
              target_side: target_side,
              round_number: round_number,
              rng: rng,
              terrain: terrain
            )
          end

          add_event(phase, "Эта фаза прошла без результата.") if phase[:events].empty?
          phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          phase
        end

        def resolve_missile_strike!(phase:, actor:, target:, vector:, attack_type:, acting_side:, target_side:, round_number:, rng:, terrain: [])
          all_combatants = acting_side[:combatants] + target_side[:combatants]
          profile = attack_type == "magic" ? SpellCasting.profile(actor) : actor
          blockers = if profile[:requires_line_of_sight]
            Geometry::Battlefield.line_of_sight_blockers(profile, target, all_combatants, terrain: terrain)
          else
            []
          end
          victims = Geometry::Battlefield.attack_victims(profile, target, target_side[:combatants], attack_type)
          return phase if victims.empty?

          host = acting_side[:combatants].find { |entry| entry[:entity_id] == actor[:host_id] } || actor
          shooting_rule = Rules.for(:shooting).find_applicable(profile, attack_type)
          custom_resolve = shooting_rule&.respond_to?(:resolve_missile_strike!)
          strikes = custom_resolve ? 1 : [ profile[:missile_attacks].to_i, 1 ].max

          strikes.times do
            if custom_resolve
              shooting_rule.resolve_missile_strike!(
                phase: phase,
                actor: actor,
                host: host,
                profile: profile,
                primary: target,
                vector: vector,
                victims: victims,
                attack_type: attack_type,
                acting_side: acting_side,
                target_side: target_side,
                round_number: round_number,
                blockers: blockers
              )
              next
            end

            victims.each do |victim_entry|
              victim = victim_entry[:target]
              next if victim[:current_health].to_i <= 0

              strike_damage = damage(profile, victim, attack_type, vector, round_number)
              strike_damage = [ 1, (strike_damage * victim_entry[:multiplier].to_f).round ].max if victim_entry[:multiplier]
              next if strike_damage <= 0

              unless hit?(profile, victim, attack_type, rng, terrain: terrain)
                add_event(phase, "#{format_actor(actor[:actor_role], actor[:actor_name])} промахивается по #{victim[:name]}.")
                next
              end

              record_missile_hit!(
                phase: phase,
                actor: actor,
                host: host,
                profile: profile,
                victim: victim,
                vector: vector,
                strike_damage: strike_damage,
                attack_type: attack_type,
                acting_side: acting_side,
                target_side: target_side,
                blockers: blockers,
                victims: victims,
                models_hit: victim_entry[:models_hit]
              )
            end
          end
          phase
        end

        def record_missile_hit!(phase:, actor:, host:, profile:, victim:, vector:, strike_damage:, attack_type:, acting_side:, target_side:, blockers:, victims:, models_hit: nil, breath: false)
          actor_state = State.snapshot_combatant(host)
          before = State.snapshot_combatant(victim)
          victim[:current_health] = [ 0, victim[:current_health] - strike_damage ].max
          State.sync_combatant_footprint!(victim)
          after = State.snapshot_combatant(victim)

          distribute_contributor_experience!(actor[:contributor] || profile, strike_damage)

          player_line =
            if breath
              Rules::Breath::Shooting.player_summary(actor, victim, models_hit, strike_damage)
            else
              missile_player_summary(actor, victim, vector, strike_damage, attack_type)
            end
          add_event(phase, player_line)
          action = {
            type: attack_type,
            actor_id: actor[:actor_id],
            actor_unit_id: actor[:host_id],
            actor_name: actor[:actor_name],
            actor_role: actor[:actor_role],
            target_id: victim[:entity_id],
            target_name: victim[:name],
            vector: vector,
            damage: strike_damage,
            models_hit: models_hit,
            blockers: blockers.map { |blocker| blocker[:entity_id] },
            requires_line_of_sight: profile[:requires_line_of_sight],
            template: template_descriptor(profile, victim, victims, attack_type),
            affected_ids: victims.map { |entry| entry[:target][:entity_id] },
            actor_state: actor_state,
            target_state_before: before,
            target_state_after: after,
            charge: nil,
            snapshot: State.snapshot_battlefield([ acting_side, target_side ])
          }
          action[:summary] = player_line
          action[:details] = details(action)
          phase[:actions] << action
        end

        def resolve_melee_strike!(phase:, attacker:, target:, vector:, acting_side:, target_side:, round_number:, rng:, terrain: [])
          blockers = []
          victims = [ { target: target, multiplier: 1 } ]
          entries = melee_entries(attacker, target, vector, round_number)

          entries.each do |entry|
            next if target[:current_health].to_i <= 0 || entry[:damage].to_i <= 0

            attacks = entry.dig(:profile, :attacks) || attacker[:attacks] || 1
            attacks.times do
              unless hit?(entry[:profile], target, "melee", rng)
                add_event(phase, "#{format_actor(entry[:actor_role], entry[:actor_name])} промахивается по #{target[:name]}.")
                next
              end

              actor_state = State.snapshot_combatant(attacker)
              before = State.snapshot_combatant(target)
              target[:current_health] = [ 0, target[:current_health] - entry[:damage] ].max
              State.sync_combatant_footprint!(target)
              after = State.snapshot_combatant(target)

              distribute_contributor_experience!(entry[:profile], entry[:damage])

              player_line = "#{format_actor(entry[:actor_role], entry[:actor_name])} бьёт #{target[:name]} (#{describe_vector(vector)}): #{entry[:damage]} урона."
              add_event(phase, player_line)
              action = {
                type: "melee",
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
                template: nil,
                affected_ids: victims.map { |victim| victim[:target][:entity_id] },
                actor_state: actor_state,
                target_state_before: before,
                target_state_after: after,
                charge: melee_charge(attacker, target, "melee", vector),
                snapshot: State.snapshot_battlefield([ acting_side, target_side ])
              }
              action[:summary] = player_line
              action[:details] = details(action)
              phase[:actions] << action
            end
          end
        end

        def damage(attacker, defender, attack_type, vector, round_number)
          base = base_power(attacker, attack_type)
          return 0 if base <= 0

          weapon_type = attack_type == "magic" ? SpellCasting.weapon_type(attacker) : attacker[:weapon_type]
          armor_factor = Constants::WEAPON_VS_ARMOR.dig(defender[:armor_type], weapon_type) || 1
          rules = Rules.for(Rules.damage_phase_for(attack_type))
          facing_factor = rules.facing_damage_factor(defender, vector)
          facing_factor = default_facing_damage_factor(vector) if facing_factor.nil?
          phase_factor = attack_type == "shooting" ? 0.9 : 1
          ability_factor = rules.damage_factor(attacker, defender, attack_type, vector, round_number)
          raw = base * armor_factor * facing_factor * phase_factor * ability_factor
          [ 1, (raw / 2.2).round ].max
        end

        def default_facing_damage_factor(vector)
          case vector.to_s
          when "rear" then 1.55
          when "flank" then 1.25
          else 1.0
          end
        end

        def hit_chance(attacker, defender, attack_type, terrain: [])
          case attack_type
          when "melee"
            attacker_skill = attacker[:skill] || 3
            defender_skill = defender[:skill] || 3
            return 5 / 6.0 if attacker_skill > defender_skill
            return 3 / 6.0 if attacker_skill < defender_skill

            4 / 6.0
          when "shooting"
            skill = (attacker[:skill] || 3).to_i
            skill -= 1 if Geometry::Battlefield.in_forest?(defender, terrain)
            [ skill, 1 ].max / 7.0
          when "magic"
            SpellCasting.hit_chance(attacker, defender)
          else
            1.0
          end
        end

        def hit?(attacker, defender, attack_type, rng, terrain: [])
          rng.rand < hit_chance(attacker, defender, attack_type, terrain: terrain)
        end

        def can_attack?(attacker, attack_type, allow_routing_melee: false)
          return false if attacker[:is_routing] && !(allow_routing_melee && attack_type == "melee")

          case attack_type
          when "magic" then SpellCasting.enabled_for?(attacker)
          when "shooting" then attacker[:ranged].to_i > 0
          else attacker[:melee].to_i > 0
          end
        end

        def choose_target(...)
          Decisions::Targeting.choose_target(...)
        end

        def can_target_missile?(...)
          Decisions::Targeting.can_target_missile?(...)
        end

        def can_target_ranged?(...)
          Decisions::Targeting.can_target_ranged?(...)
        end

        def in_melee_combat?(...)
          Decisions::Targeting.in_melee_combat?(...)
        end

        def same_side?(...)
          Decisions::Targeting.same_side?(...)
        end

        def melee_contact?(...)
          Decisions::Targeting.melee_contact?(...)
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
          when "magic" then SpellCasting.base_power(attacker)
          when "shooting" then attacker[:ranged].to_i
          else attacker[:melee].to_i
          end
        end

        def distribute_contributor_experience!(contributor, damage)
          return unless contributor[:kind] == "hero"

          contributor[:experience_gain] += [ 1, damage ].max
        end

        def vector_priority(...)
          Decisions::Targeting.vector_priority(...)
        end

        def prioritize_routing(...)
          Decisions::Targeting.prioritize_routing(...)
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
          rule = Rules.for(:shooting).find_applicable(attacker, attack_type)
          return rule.template_descriptor(attacker, target, victims) if rule&.respond_to?(:template_descriptor)

          kind = attack_type == "magic" ? SpellCasting.template_kind(attacker) : attacker[:shooting_template]
          {
            shape: "line",
            start: { x: attacker[:x], y: attacker[:y] },
            end: { x: target[:x], y: target[:y] },
            kind: kind,
            affected_ids: victims.map { |entry| entry[:target][:entity_id] }
          }
        end

        def summarize(action, phase_type)
          actor = format_actor(action[:actor_role], action[:actor_name])
          case phase_type
          when "shooting"
            "#{actor} стреляет в #{action[:target_name]} (#{describe_vector(action[:vector])}): #{action[:damage]} урона."
          when "magic"
            "#{actor} бьёт магией #{action[:target_name]} (#{describe_vector(action[:vector])}): #{action[:damage]} урона."
          else
            "#{actor} бьёт #{action[:target_name]} (#{describe_vector(action[:vector])}): #{action[:damage]} урона."
          end
        end

        def missile_player_summary(actor, target, vector, damage, attack_type)
          summarize(
            {
              actor_role: actor[:actor_role],
              actor_name: actor[:actor_name],
              target_name: target[:name],
              vector: vector,
              damage: damage
            },
            attack_type
          )
        end

        def details(action)
          before = action[:target_state_before]
          after = action[:target_state_after]
          actor = action[:actor_state]
          lines = [
            "actor=#{action[:actor_id]} #{action[:actor_name]} role=#{action[:actor_role]} type=#{action[:type]}",
            "target=#{action[:target_id]} #{action[:target_name]} vector=#{action[:vector]} damage=#{action[:damage]}",
            "target HP #{before && before[:current_health]}/#{before && before[:max_health]} → #{after && after[:current_health]}/#{after && after[:max_health]}, models #{before && before[:models_remaining]} → #{after && after[:models_remaining]}"
          ]
          if actor
            lines << "attacker pose/state: #{format_state(actor)}"
          end
          lines << "affected_ids=#{Array(action[:affected_ids]).join(",")}"
          lines << "models_hit=#{action[:models_hit]}" if action[:models_hit]
          lines << "blockers=#{Array(action[:blockers]).join(",")}" if Array(action[:blockers]).any?
          if action[:template]
            tmpl = action[:template]
            lines << "template=#{tmpl[:kind] || tmpl[:shape]} shape=#{tmpl[:shape]} length=#{tmpl[:length]}"
            if tmpl[:points]
              pts = tmpl[:points].map { |p| "(#{format('%.2f', p[:x])},#{format('%.2f', p[:y])})" }.join(" ")
              lines << "template_points=#{pts}"
            end
          end
          if action[:charge]
            charge = action[:charge]
            lines << "charge start=(#{charge.dig(:start, :x)}, #{charge.dig(:start, :y)}) dest=(#{charge.dig(:destination, :x)}, #{charge.dig(:destination, :y)})"
          end
          lines << "requires_los=#{action[:requires_line_of_sight]}"
          lines
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
