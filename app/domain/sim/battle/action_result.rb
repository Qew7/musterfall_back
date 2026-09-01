module Sim
  module Battle
    class ActionResult
      STAT_LABELS = {
        movement: "MV",
        skill: "SK",
        melee: "ML",
        ranged: "RG",
        morale: "MO",
        spell: "SP"
      }.freeze

      WEAPON_LABELS = {
        "slash" => "рубящим",
        "blunt" => "дробящим",
        "puncture" => "колющим",
        "ranged" => "стрелковым",
        "magic" => "магическим",
        "breath" => "огненным дыханием",
        "demolish" => "осадным",
        "fire" => "огненным",
        "lightning" => "молниевым",
        "nature" => "природным",
        "shadow" => "теневым",
        "death" => "мертвенным",
        "chaos" => "хаотическим"
      }.freeze

      ARMOR_LABELS = {
        "heavy" => "тяжёлой",
        "medium" => "средней",
        "light" => "лёгкой",
        "machine" => "машинной",
        "magic" => "магической"
      }.freeze

      VECTOR_LABELS = { "rear" => "тыл", "flank" => "фланг", "front" => "фронт" }.freeze
      OUTCOMES = { "success" => "успех", "failed" => "провал", "miscast" => "дикая магия" }.freeze
      MANEUVER_LABELS = {
        "turn" => "поворот",
        "wheel" => "колесо",
        "advance" => "продвижение",
        "march" => "марш"
      }.freeze

      def self.text_for(actor: {}, action:, before: [], after: [], **meta)
        new(actor: actor, action: action, before: before, after: after, meta: meta).text
      end

      def self.movement_summary(actor:, motions:, target_name: nil, note: nil, context: :approach)
        actor_label = new(actor: actor, action: {}, before: [], after: [], meta: {}).send(:format_actor)
        kinds = Array(motions).filter_map { |motion| (motion[:kind] || motion["kind"]).to_s.presence }
        if kinds.empty?
          return hold_summary(actor_label, target_name, note, context)
        end

        phrases = kinds.map { |kind| MANEUVER_LABELS[kind] || kind }
        maneuver_text =
          if phrases.length == 1
            "совершил #{phrases.first}"
          else
            "совершил #{phrases.first}, затем #{phrases.drop(1).join(', затем ')}"
          end

        body =
          case context
          when :reposition
            target = target_name.presence || "противника"
            "#{actor_label} #{maneuver_text}, занимая позицию против #{target}"
          when :wait
            "#{actor_label} #{maneuver_text}"
          else
            target = target_name.presence
            if target
              "#{actor_label} #{maneuver_text} к #{target}"
            else
              "#{actor_label} #{maneuver_text}"
            end
          end

        suffix = note.to_s.strip
        suffix = ", #{suffix}" if suffix.present? && !suffix.start_with?(",")
        "#{body}#{suffix}."
      end

      def self.hold_summary(actor_label, target_name, note, context)
        case context
        when :reposition
          target = target_name.presence || "противника"
          "#{actor_label} занимает позицию против #{target}#{note}."
        when :wait
          "#{actor_label} ждёт#{note}."
        else
          target = target_name.presence
          if target
            "#{actor_label} сближается с #{target}#{note}."
          else
            "#{actor_label} остаётся на месте#{note}."
          end
        end
      end
      private_class_method :hold_summary

      def self.append_clause!(action, text)
        return if text.blank?

        (action[:clauses] ||= []) << text.to_s
      end

      def initialize(actor:, action:, before:, after:, meta: {})
        @actor = actor || {}
        @action = action
        @before = Array(before).compact
        @after = Array(after).compact.index_by { |entry| entry[:entity_id] }
        @meta = meta
      end

      def text
        return strike_text if strike?
        return bolt_text if action_type == "magic" && spell.nil?
        return spell_text if spell

        rule_text
      end

      private

      def strike?
        %w[melee shooting].include?(action_type)
      end

      def spell
        @action if @action.respond_to?(:key) && !@action.is_a?(Hash)
      end

      def action_type
        return "magic" if spell
        return @action[:type].to_s if @action.is_a?(Hash)

        @action.to_s
      end

      def strike_text
        @before.filter_map { |prior| strike_line(prior, @after[prior[:entity_id]]) }.join(" ").presence
      end

      def strike_line(prior, later)
        return unless later

        damage = dealt_damage(prior, later)
        weapon = WEAPON_LABELS[weapon_type.to_s]
        armor = ARMOR_LABELS[later[:armor_type].to_s]
        vs = weapon && armor ? " #{weapon} оружием по #{armor} броне" : ""
        facing = VECTOR_LABELS[@meta[:vector].to_s]
        facing = facing ? " (#{facing})" : ""
        roll = attack_roll_text
        roll = roll ? "#{roll}, " : ""
        line = "#{format_actor} наносит #{later[:name]}#{vs}#{facing}: #{roll}#{damage} урона, #{remaining_models_text(later)}"
        extras = extras_text
        extras.present? ? "#{line}; #{extras}." : "#{line}."
      end

      def attack_roll_text
        attempts = @meta[:attacks_attempted].to_i
        hits = @meta[:hits_landed].to_i
        return nil unless attempts.positive?

        "попало #{hits} из #{attempts} атак"
      end

      def bolt_text
        target = @meta[:target_name] || @meta[:target_label] || @before.first&.[](:name)
        school_key = (@meta[:magic_school] || @actor[:magic_school] || @action[:magic_school]).to_s.to_sym
        school = Spells::SCHOOL_METADATA.dig(school_key, :name) || school_key
        facing = VECTOR_LABELS[@meta[:vector].to_s] || "фронт"
        prior = @before.first
        later = @after[prior&.[](:entity_id)]
        bits = [ attack_roll_text, "#{dealt_damage(prior, later)} урона" ].compact
        bits << remaining_models_text(later) if later
        "#{format_actor} направляет силу школы «#{school}» на #{target} (#{facing}): #{bits.join(', ')}."
      end

      def spell_text
        body = interpolate_log
        tail = [ outcome_clause, damage_clause, changes_text, extras_text ].compact_blank.join(", ")
        tail.present? ? "#{body}: #{tail}." : "#{body}."
      end

      def interpolate_log
        template = spell::LOG
        template = template[@meta[:outcome].to_s.to_sym] || template[:success] || template.values.first if template.is_a?(Hash)
        template.to_s % { caster: format_actor, target: target_label, spell: spell.name }
      end

      def outcome_clause
        return unless @meta[:dice]

        label = OUTCOMES[@meta[:outcome].to_s]
        dice = Array(@meta[:dice])
        "#{label} (#{dice.join('+')}+#{@meta[:spell_power]}=#{@meta[:casting_total]} против #{@meta[:casting_value]})" if label
      end

      def damage_clause
        prior = @before.first
        later = prior && @after[prior[:entity_id]]
        damage = later ? dealt_damage(prior, later) : @meta[:damage].to_i
        "#{damage} урона" if damage.positive?
      end

      def changes_text
        @changes_text ||= @before.filter_map { |prior| change_line(prior, @after[prior[:entity_id]]) }.join("; ").presence
      end

      def change_line(prior, later)
        return unless later

        bits = STAT_LABELS.filter_map do |stat, label|
          from = prior[stat]
          to = later[stat]
          next if from.to_f == to.to_f

          verb = to.to_f > from.to_f ? "увеличился" : "уменьшился"
          "#{label} #{verb} с #{format_stat(from)} до #{format_stat(to)}"
        end
        if prior[:models_remaining].to_i != later[:models_remaining].to_i ||
            (later[:model_health].to_i > 1 && prior[:current_health].to_i != later[:current_health].to_i)
          bits << remaining_models_text(later)
        end
        return if bits.empty?

        "у #{later[:name]} #{bits.join(', ')}"
      end

      def rule_text
        body = Array(@meta[:clauses]).join(" ").presence || format_actor
        tail = [ damage_clause, changes_text, extras_text(include_clauses: false) ].compact_blank.join(", ")
        tail.present? ? "#{body.sub(/[。.]\z/, '')}: #{tail}." : "#{body.sub(/[。.]\z/, '')}."
      end

      def extras_text(include_clauses: true)
        bits = include_clauses ? Array(@meta[:clauses]).compact_blank : []
        bits.concat(Array(@meta[:effects]).filter_map { |effect| extra_effect(effect) })
        bits << "изменён ландшафт" if Array(@meta[:terrain_delta]).any? && Array(@meta[:clauses]).blank?
        bits << "призвано существ: #{Array(@meta[:summon_ids]).size}" if Array(@meta[:summon_ids]).any?
        bits.join(", ").presence
      end

      def extra_effect(effect)
        case effect[:kind].to_s
        when "effect"
          return if changes_text.present?

          key = effect.dig(:effect, :key)
          "эффект «#{Spells.fetch(key)&.name || key.to_s.tr('_', ' ')}»"
        when "heal"
          "восстановлено #{effect[:amount]} здоровья"
        when "teleport", "move"
          pose = effect[:to]
          pose.is_a?(Hash) ? "цель перемещена в #{pose[:x].to_f.round(1)}, #{pose[:y].to_f.round(1)}" : "цель перемещена"
        when "rotate"
          "цель развёрнута"
        when "scheduled"
          "эффект сработает позже"
        end
      end

      def target_label
        return @meta[:target_label] if @meta[:target_label].present?
        return "цели" if @before.size > 1

        @before.first&.[](:name) || "цель"
      end

      def weapon_type
        @meta[:weapon_type] || @actor[:weapon_type]
      end

      def format_actor
        name = @actor[:actor_name] || @actor[:name]
        return name.to_s if name.blank?

        @actor[:actor_role].to_s == "hero" ? "Герой #{name}" : "Отряд #{name}"
      end

      def self.miss_roll_text(actor:, target_name:, hits_landed:, attacks_attempted:)
        actor_label = new(actor: actor, action: {}, before: [], after: [], meta: {}).send(:format_actor)
        "#{actor_label} атакует #{target_name}: попало #{hits_landed.to_i} из #{attacks_attempted.to_i} атак."
      end

      def format_stat(value)
        number = value.to_f
        number == number.to_i ? number.to_i : number.round(1)
      end

      def dealt_damage(prior, later)
        return @meta[:damage].to_i unless prior && later

        delta = prior[:current_health].to_i - later[:current_health].to_i
        delta.positive? ? delta : @meta[:damage].to_i
      end

      def remaining_models_text(state)
        models = state[:models_remaining].to_i
        line = "осталось #{models} моделей"
        model_health = state[:model_health].to_i
        return line if model_health <= 1

        current = state[:current_health].to_i
        cap = state[:max_health].to_i
        cap = model_health if models <= 1 && state[:kind].to_s != "hero"
        "#{line}, здоровье #{current}/#{cap}"
      end
    end
  end
end
