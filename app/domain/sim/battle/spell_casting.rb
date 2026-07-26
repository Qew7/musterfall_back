module Sim
  module Battle
    # Current magic-attack rules live here on purpose.
    # Swap or rewrite this module when spellcasting becomes a different mechanic;
    # callers should depend only on these methods, not on AttackResolution magic branches.
    module SpellCasting
      module_function

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
    end
  end
end
