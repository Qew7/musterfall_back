module Sim
  module Battle
    module Trace
      VERSION = 1
      PHASE_RULE_KEYS = {
        movement: %w[flying march outrider forestborn wildborn throwRocks],
        melee: %w[charge momentumCharge boarCharge ferocious supportRank shieldwall antiLarge armorPiercing dodge poison toxin runeArmor skirmisher forestkin],
        shooting: %w[breath common volley blast line machine slingCatapult corpseTrail armorPiercing dodge toxin runeArmor forestborn skirmisher],
        magic: %w[breath common volley blast line machine armorPiercing dodge toxin runeArmor skirmisher],
        morale: %w[undead fear undaunted wildborn disciplined resolute muster],
        round: %w[regen forestkin]
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
        keys << "march" if maneuver && (maneuver[:kind].to_s == "march" || maneuver[:march].to_s == "active")
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
