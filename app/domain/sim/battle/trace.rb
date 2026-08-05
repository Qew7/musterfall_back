module Sim
  module Battle
    module Trace
      VERSION = 1
      PHASE_RULE_KEYS = {
        movement: %w[flying march],
        melee: %w[charge ferocious steadfast skirmisher],
        shooting: %w[breath volley blast machine steadfast skirmisher],
        magic: %w[breath volley blast machine steadfast skirmisher],
        morale: %w[undead fear disciplined muster]
      }.freeze

      module_function

      def build(rule_keys: [], trigger:, result:, target_ids: [])
        {
          version: VERSION,
          rule_keys: Array(rule_keys).compact.map(&:to_s).uniq.sort,
          trigger: trigger.to_s,
          result: result.to_s,
          target_ids: Array(target_ids).compact.map(&:to_s).uniq
        }
      end

      def rule_keys_for(combatant, phase)
        abilities = Array(combatant && combatant[:abilities]).map(&:to_s)
        abilities & PHASE_RULE_KEYS.fetch(phase.to_sym, [])
      end

      def movement_rule_keys(combatant, maneuver)
        keys = rule_keys_for(combatant, :movement)
        keys << "march" if maneuver && maneuver[:march].to_s == "active"
        keys << "flying" if maneuver && maneuver[:kind].to_s.start_with?("flyer_")
        keys.uniq
      end

      def attack_rule_keys(attacker, attack_type, profile: nil)
        phase = attack_type.to_s == "melee" ? :melee : attack_type.to_sym
        keys = rule_keys_for(attacker, phase)
        source = profile || attacker || {}
        template = source[:shooting_template] || source[:spell_template]
        keys << template.to_s if PHASE_RULE_KEYS.fetch(phase, []).include?(template.to_s)
        keys.uniq
      end
    end
  end
end
