module Sim
  module Battle
    module SpellEffects
      NUMERIC_STATS = %i[melee ranged spell skill morale movement attacks].freeze

      module_function

      def add!(combatant, key:, modifiers: {}, statuses: [], triggers: {}, expires:)
        normalized = modifiers.to_h.transform_keys(&:to_sym)
        normalized.each do |stat, amount|
          next unless NUMERIC_STATS.include?(stat)

          combatant[stat] = combatant[stat].to_f + amount.to_f
        end
        effect = {
          key: key.to_s,
          modifiers: normalized,
          statuses: Array(statuses).map(&:to_s),
          triggers: triggers.to_h.deep_symbolize_keys,
          expires: expires,
          contributor_modifiers: apply_contributor_modifiers!(combatant, normalized)
        }
        combatant[:spell_effects] ||= []
        combatant[:spell_effects] << effect
        effect
      end

      def expire!(sides, moment:, side_key:)
        Array(sides).each do |side|
          Array(side[:combatants]).each do |combatant|
            expired, active = Array(combatant[:spell_effects]).partition do |effect|
              expiry = effect[:expires] || {}
              next false unless expiry[:side_key].to_s == side_key.to_s

              if expiry[:moment].to_s == "turns" && moment.to_sym == :end_turn
                expiry[:remaining_turns] = expiry[:remaining_turns].to_i - 1
                expiry[:remaining_turns] <= 0
              else
                expiry[:moment].to_s == moment.to_s
              end
            end
            expired.each { |effect| revert!(combatant, effect) }
            combatant[:spell_effects] = active
          end
        end
      end

      def armor_factor(combatant)
        Array(combatant[:spell_effects]).reduce(1.0) do |factor, effect|
          modifier = effect.dig(:modifiers, :armor_factor)
          modifier ? factor * modifier.to_f.clamp(0.1, 10.0) : factor
        end
      end

      def status?(combatant, status)
        Array(combatant[:spell_effects]).any? { |effect| Array(effect[:statuses]).include?(status.to_s) }
      end

      def triggers(combatant, event)
        Array(combatant[:spell_effects]).filter_map do |effect|
          payload = effect.dig(:triggers, event.to_sym)
          [ effect, payload ] if payload
        end
      end

      def public_for(combatant)
        Array(combatant[:spell_effects]).map do |effect|
          effect.slice(:key, :modifiers, :statuses, :triggers, :expires)
        end
      end

      def revert!(combatant, effect)
        effect.fetch(:modifiers, {}).each do |stat, amount|
          next unless NUMERIC_STATS.include?(stat)

          combatant[stat] = combatant[stat].to_f - amount.to_f
        end
        Array(effect[:contributor_modifiers]).each do |entry|
          contributor = entry[:contributor]
          contributor[entry[:stat]] = contributor[entry[:stat]].to_f - entry[:amount].to_f
        end
      end
      private_class_method :revert!

      def apply_contributor_modifiers!(combatant, modifiers)
        applied = []
        if modifiers.key?(:melee)
          contributor = Array(combatant.dig(:contributors, :melee)).find { |entry| entry[:power].to_f.positive? }
          if contributor
            contributor[:power] = contributor[:power].to_f + modifiers[:melee].to_f
            applied << { contributor: contributor, stat: :power, amount: modifiers[:melee] }
          end
        end
        %i[ranged spell].each do |stat|
          next unless modifiers.key?(stat)

          contributor = Array(combatant.dig(:contributors, :ranged)).max_by { |entry| entry[stat].to_f }
          next unless contributor

          contributor[stat] = contributor[stat].to_f + modifiers[stat].to_f
          applied << { contributor: contributor, stat: stat, amount: modifiers[stat] }
        end
        if modifiers.key?(:skill)
          (Array(combatant.dig(:contributors, :melee)) + Array(combatant.dig(:contributors, :ranged))).uniq.each do |contributor|
            contributor[:skill] = contributor[:skill].to_f + modifiers[:skill].to_f
            applied << { contributor: contributor, stat: :skill, amount: modifiers[:skill] }
          end
        end
        applied
      end
      private_class_method :apply_contributor_modifiers!
    end
  end
end
