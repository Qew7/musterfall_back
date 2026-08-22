module Sim
  module Battle
    module SpellCasting
      module_function

      def play!(phase:, acting_side:, target_side:, round_number:, rng:, terrain: [])
        process_scheduled!(
          phase: phase,
          acting_side: acting_side,
          target_side: target_side,
          round_number: round_number,
          rng: rng,
          terrain: terrain
        )
        all_combatants = acting_side[:combatants] + target_side[:combatants]
        casters(acting_side).sort_by { |entry| -entry[:caster][:initiative].to_i }.each do |entry|
          caster = entry[:caster]
          host = entry[:host]
          next if Decisions::Targeting.in_melee_combat?(host, all_combatants)

          choice = choose_spell(
            caster: caster,
            host: host,
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            rng: rng,
            terrain: terrain
          )
          next unless choice

          resolve_choice!(
            phase: phase,
            choice: choice,
            caster: caster,
            host: host,
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            rng: rng,
            terrain: terrain
          )
        end
        phase
      end

      def casters(acting_side)
        acting_side[:combatants].filter_map do |host|
          next if host[:current_health].to_i <= 0 || host[:is_routing] || host[:summoned]

          Array(host.dig(:contributors, :ranged)).filter_map do |contributor|
            next if contributor[:spell].to_i <= 0 || Array(contributor[:spell_keys]).empty?

            { host: host, caster: Decisions::MissileChoice.build_actor(host, contributor) }
          end
        end.flatten
      end

      def choose_spell(caster:, host:, acting_side:, target_side:, round_number:, rng:, terrain:)
        Array(caster[:spell_keys]).flat_map do |key|
          spell = Spells.fetch(key)
          next [] unless spell

          context = SpellContext.new(
            caster: caster,
            host: host,
            acting_side: acting_side,
            target_side: target_side,
            terrain: terrain,
            rng: rng,
            round_number: round_number,
            spell: spell
          )
          Array(spell.legal_targets(context)).filter_map do |target|
            next if spell.requires_los? && target.is_a?(Hash) && target[:x] && !context.visible?(target)

            { spell: spell, target: target, score: spell.score(context, target).to_f }
          end
        end.max_by do |entry|
          target = entry[:target]
          [ entry[:score], target_sort_key(target), entry[:spell].key.to_s ]
        end
      end

      def resolve_choice!(phase:, choice:, caster:, host:, acting_side:, target_side:, round_number:, rng:, terrain:)
        spell = choice[:spell]
        target = choice[:target]
        context = SpellContext.new(
          caster: caster,
          host: host,
          acting_side: acting_side,
          target_side: target_side,
          terrain: terrain,
          rng: rng,
          round_number: round_number,
          spell: spell
        )
        units = acting_side[:combatants] + target_side[:combatants]
        unit_before = units.map { |unit| State.snapshot_combatant(unit) }
        before = State.snapshot_battlefield([ acting_side, target_side ])
        dice = [ rng.rand(6) + 1, rng.rand(6) + 1 ]
        casting_total = dice.sum + caster[:spell].to_i
        miscast = dice == [ 1, 1 ]
        success = !miscast && casting_total >= spell.casting_value.to_i

        target_label = describe_target(target)
        power = caster[:spell].to_i
        if miscast
          damage = [ 1, host[:current_health].to_i ].min
          host[:current_health] -= damage
          State.sync_combatant_footprint!(host)
          outcome = "miscast"
          result = { damage: damage, affected_ids: [ host[:entity_id] ], effects: [], terrain_delta: [], summon_ids: [] }
        elsif success
          spell.resolve!(context, target)
          outcome = "success"
          result = context.result
        else
          outcome = "failed"
          result = { damage: 0, affected_ids: [], effects: [], terrain_delta: [], summon_ids: [] }
        end

        summary = ActionResult.text_for(
          actor: caster,
          action: spell,
          before: unit_before,
          after: units.map { |unit| State.snapshot_combatant(unit) },
          target_label: target_label,
          outcome: outcome,
          dice: dice,
          spell_power: power,
          casting_total: casting_total,
          casting_value: spell.casting_value,
          damage: result[:damage],
          effects: result[:effects],
          terrain_delta: result[:terrain_delta],
          summon_ids: result[:summon_ids]
        )

        template = success ? build_spell_template(
          spell,
          caster: caster,
          host: host,
          target: target,
          result: result,
          sides: [ acting_side, target_side ]
        ) : nil

        action = {
          type: "magic",
          actor_id: caster[:actor_id],
          actor_unit_id: host[:entity_id],
          actor_name: caster[:actor_name],
          actor_role: caster[:actor_role],
          target_id: target_identifier(target),
          target_name: target.is_a?(Hash) && target[:name],
          spell_key: spell.key.to_s,
          magic_school: caster[:magic_school],
          casting_value: spell.casting_value,
          dice: dice,
          spell_power: power,
          casting_total: casting_total,
          outcome: outcome,
          damage: result[:damage],
          affected_ids: result[:affected_ids],
          effects: result[:effects],
          terrain_delta: result[:terrain_delta],
          summon_ids: result[:summon_ids],
          template: template,
          state_before: before,
          summary: summary,
          details: [
            "spell=#{spell.key} school=#{caster[:magic_school]} casting_value=#{spell.casting_value}",
            "dice=#{dice.join('+')} spell_power=#{caster[:spell]} total=#{casting_total} outcome=#{outcome}",
            "affected=#{Array(result[:affected_ids]).join(',')} damage=#{result[:damage]}",
            *analysis_lines(result),
            *Array(template_analysis_line(template))
          ],
          trace: Trace.build(
            rule_keys: [ caster[:magic_school], spell.key ],
            trigger: "spell_cast",
            result: outcome,
            target_ids: result[:affected_ids]
          ),
          snapshot: State.snapshot_battlefield([ acting_side, target_side ])
        }
        Phases::AttackResolution.add_event(phase, summary)
        phase[:actions] << action
        action
      end

      def process_scheduled!(phase:, acting_side:, target_side:, round_number:, rng:, terrain:)
        due, pending = Array(acting_side[:scheduled_spells]).partition { |event| event[:due_round].to_i <= round_number.to_i }
        acting_side[:scheduled_spells] = pending
        due.each do |event|
          next unless event[:kind] == "comet"

          point = event[:target]
          victims = target_side[:combatants].select do |target|
            target[:current_health].to_i > 0 && Geometry::Battlefield.distance_between(point, target) <= 2.5
          end
          unit_before = victims.map { |victim| State.snapshot_combatant(victim) }
          damage = 0
          victims.each do |victim|
            amount = [ 1, (6 * (Constants::WEAPON_VS_ARMOR.dig(victim[:armor_type], "demolish") || 1) / 2.2).round ].max
            amount = [ amount, victim[:current_health].to_i ].min
            victim[:current_health] -= amount
            State.sync_combatant_footprint!(victim)
            damage += amount
          end
          spell = Spells.fetch(event[:spell_key])
          summary = ActionResult.text_for(
            actor: { actor_role: event[:actor_role], actor_name: event[:actor_name] },
            action: spell,
            before: unit_before,
            after: victims.map { |victim| State.snapshot_combatant(victim) },
            target_label: "поле боя",
            outcome: "delayed",
            damage: damage
          )
          Phases::AttackResolution.add_event(phase, summary)
          phase[:actions] << {
            type: "magic",
            actor_id: event[:caster_id],
            spell_key: event[:spell_key],
            outcome: "delayed",
            target_id: point[:entity_id],
            damage: damage,
            affected_ids: victims.map { |victim| victim[:entity_id] },
            template: {
              shape: "circle",
              kind: event[:spell_key].to_s,
              radius: 2.5,
              center: { x: point[:x].to_f, y: point[:y].to_f },
              affected_ids: victims.map { |victim| victim[:entity_id] }
            },
            summary: summary,
            details: [ "scheduled=comet due_round=#{round_number}", "damage=#{damage}" ],
            trace: Trace.build(rule_keys: [ event[:spell_key] ], trigger: "scheduled_spell", result: "hit", target_ids: victims.map { |victim| victim[:entity_id] }),
            snapshot: State.snapshot_battlefield([ acting_side, target_side ])
          }
        end
      end

      def enabled_for?(caster)
        caster[:spell].to_i > 0
      end

      def hit_chance(_caster, _target)
        1.0
      end

      def weapon_type(_caster)
        "magic"
      end

      def template_kind(caster)
        caster[:spell_template].presence || "single"
      end

      def build_spell_template(spell, caster:, host:, target:, result:, sides: [])
        visual = spell.respond_to?(:visual_template) ? spell.visual_template : nil
        return nil unless visual.is_a?(Hash)

        shape = visual[:shape].to_s
        kind = spell.key.to_s
        affected = Array(result[:affected_ids])
        origin = pose_of(host) || pose_of(caster)
        focus = pose_of(target) || origin
        case shape
        when "circle"
          {
            shape: "circle",
            kind: kind,
            radius: visual.fetch(:radius, 4.0).to_f,
            center: focus,
            affected_ids: affected
          }
        when "aura"
          {
            shape: "circle",
            kind: kind,
            radius: visual.fetch(:radius, 4.0).to_f,
            center: origin,
            affected_ids: affected
          }
        when "line"
          return nil unless origin && focus

          {
            shape: "line",
            kind: kind,
            start: origin,
            end: focus,
            affected_ids: affected
          }
        when "chain"
          points = chain_template_points(target, affected, sides)
          return nil if points.size < 2

          {
            shape: "polygon",
            kind: kind,
            points: points,
            affected_ids: affected
          }
        end
      end
      private_class_method :build_spell_template

      def pose_of(entry)
        return nil unless entry.is_a?(Hash) && entry.key?(:x) && entry.key?(:y)

        { x: entry[:x].to_f, y: entry[:y].to_f }
      end
      private_class_method :pose_of

      def chain_template_points(primary, affected_ids, sides)
        by_id = Array(sides).flat_map { |side| Array(side[:combatants]) }.index_by { |entry| entry[:entity_id] }
        ordered = [ primary.is_a?(Hash) ? primary[:entity_id] : nil, *Array(affected_ids) ].compact.uniq
        ordered.filter_map { |id| pose_of(by_id[id]) || (primary.is_a?(Hash) && primary[:entity_id] == id ? pose_of(primary) : nil) }
      end
      private_class_method :chain_template_points

      def base_power(caster)
        caster[:spell].to_i
      end

      def profile(caster)
        caster.merge(
          spell: base_power(caster),
          weapon_type: weapon_type(caster),
          spell_template: template_kind(caster)
        )
      end

      # Expected damage if this caster casts now. `damage_fn` keeps numeric rules centralized.
      def expected_damage(caster, target, vector:, round_number:, attacks:, damage_fn:)
        return 0.0 unless enabled_for?(caster)

        strikes = [ attacks.to_i, 1 ].max
        hit_chance(caster, target) * damage_fn.call(profile(caster), target, "magic", vector, round_number) * strikes
      end

      def target_sort_key(target)
        return "" unless target.is_a?(Hash)

        target[:entity_id].to_s.presence || target[:id].to_s.presence || format("%08.3f:%08.3f", target[:x].to_f, target[:y].to_f)
      end
      private_class_method :target_sort_key

      def target_identifier(target)
        return nil unless target.is_a?(Hash)

        target[:entity_id] || target[:id] || "point:#{target[:x].to_f.round(2)},#{target[:y].to_f.round(2)}"
      end
      private_class_method :target_identifier

      def describe_target(target)
        return Spells.target_label(:battlefield) unless target.is_a?(Hash)
        return target[:name] if target[:name].present?
        return Spells.target_label(:battlefield_point) if target.key?(:x)

        Spells.target_label(:battlefield)
      end
      private_class_method :describe_target

      def analysis_lines(result)
        lines = Array(result[:effects]).filter_map { |effect| effect_analysis_line(effect) }
        lines.concat(Array(result[:terrain_delta]).filter_map { |change| terrain_analysis_line(change) })
        lines
      end
      private_class_method :analysis_lines

      def effect_analysis_line(effect)
        case effect[:kind].to_s
        when "teleport", "move"
          "teleport id=#{effect[:target_id]} from=#{format_pose(effect[:from])} to=#{format_pose(effect[:to])}"
        when "rotate"
          "rotate id=#{effect[:target_id]} from=#{effect[:from]} to=#{effect[:to]}"
        when "summon"
          remaining = effect[:remaining_turns] ? " remaining=#{effect[:remaining_turns]}" : ""
          "summon id=#{effect[:summon_id]} kind=#{effect[:summon_kind]}#{remaining}"
        end
      end
      private_class_method :effect_analysis_line

      def terrain_analysis_line(change)
        feature = change[:feature] || {}
        "terrain #{change[:operation]} id=#{feature[:id]} type=#{feature[:type]} " \
          "x=#{feature[:x]} y=#{feature[:y]} w=#{feature[:width]} d=#{feature[:depth]}"
      end
      private_class_method :terrain_analysis_line

      def template_analysis_line(template)
        return nil unless template.is_a?(Hash)

        case template[:shape].to_s
        when "circle"
          "template shape=circle kind=#{template[:kind]} r=#{template[:radius]} " \
            "center=#{template.dig(:center, :x)},#{template.dig(:center, :y)}"
        when "line"
          "template shape=line kind=#{template[:kind]} " \
            "from=#{template.dig(:start, :x)},#{template.dig(:start, :y)} " \
            "to=#{template.dig(:end, :x)},#{template.dig(:end, :y)}"
        when "polygon"
          "template shape=polygon kind=#{template[:kind]} points=#{Array(template[:points]).size}"
        end
      end
      private_class_method :template_analysis_line

      def format_pose(pose)
        return "" unless pose.is_a?(Hash)

        "#{pose[:x].to_f.round(2)},#{pose[:y].to_f.round(2)},#{pose[:facing].to_f.round(1)}"
      end
      private_class_method :format_pose
    end
  end
end
