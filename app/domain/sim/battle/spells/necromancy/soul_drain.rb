module Sim::Battle::Spells::Necromancy
  class SoulDrain
    extend Contract
    KEY = :soul_drain
    NAME = "Soul Drain"
    DESCRIPTION = "Steals vitality from an enemy unit."
    CASTING_VALUE = 9
    TARGET_TYPE = :enemy_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :life_drain
    LOG = "%{caster} иссушает душу %{target}"
    EFFECT = ->(context, target) { context.damage!(target, amount: 3, type: :death, heal_caster: 2) }
  end
end
