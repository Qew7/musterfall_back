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

      def self.text_for(actor: {}, action:, before: [], after: [], **meta)
        new(actor: actor, action: action, before: before, after: after, meta: meta).text
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

        spell_text
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

        damage = @meta[:damage] || (prior[:current_health].to_i - later[:current_health].to_i)
        weapon = WEAPON_LABELS[weapon_type.to_s]
        armor = ARMOR_LABELS[later[:armor_type].to_s]
        vs = weapon && armor ? " #{weapon} оружием по #{armor} броне" : ""
        facing = VECTOR_LABELS[@meta[:vector].to_s]
        facing = facing ? " (#{facing})" : ""
        "#{format_actor} наносит #{later[:name]}#{vs}#{facing}: #{damage} урона, осталось #{later[:models_remaining].to_i} моделей."
      end

      def bolt_text
        target = @meta[:target_name] || @meta[:target_label] || @before.first&.[](:name)
        school_key = (@meta[:magic_school] || @actor[:magic_school] || @action[:magic_school]).to_s.to_sym
        school = Spells::SCHOOL_METADATA.dig(school_key, :name) || school_key
        facing = VECTOR_LABELS[@meta[:vector].to_s] || "фронт"
        later = @after[@before.first&.[](:entity_id)]
        bits = [ "#{@meta[:damage].to_i} урона" ]
        bits << "осталось #{later[:models_remaining].to_i} моделей" if later
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
        "#{@meta[:damage]} урона" if @meta[:damage].to_i.positive?
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
        if prior[:models_remaining].to_i != later[:models_remaining].to_i
          bits << "осталось #{later[:models_remaining].to_i} моделей"
        end
        return if bits.empty?

        "у #{later[:name]} #{bits.join(', ')}"
      end

      def extras_text
        bits = Array(@meta[:effects]).filter_map { |effect| extra_effect(effect) }
        bits << "изменён ландшафт" if Array(@meta[:terrain_delta]).any?
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

      def format_stat(value)
        number = value.to_f
        number == number.to_i ? number.to_i : number.round(1)
      end
    end
  end
end
