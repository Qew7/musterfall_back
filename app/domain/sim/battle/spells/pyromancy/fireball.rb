module Sim::Battle::Spells::Pyromancy
  class Fireball
    extend Contract
    KEY = :fireball
    NAME = "Fireball"
    DESCRIPTION = "Hurls a ball of flame at an enemy unit."
    CASTING_VALUE = 8
    TARGET_TYPE = :enemy_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :direct_damage
    LOG = "%{caster} швыряет огненный шар в %{target}"
    EFFECT = ->(context, target) { context.damage!(target, amount: 3, type: :fire) }
  end
end
