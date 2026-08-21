module Sim::Battle::Spells::Celestial
  class ChainLightning
    extend Contract
    KEY = :chain_lightning
    NAME = "Chain Lightning"
    DESCRIPTION = "Lightning leaps between nearby enemy units."
    CASTING_VALUE = 11
    TARGET_TYPE = :enemy_unit
    REQUIRES_LOS = true
    TEMPLATE = { shape: "chain" }
    SCORE_PROFILE = :chain_damage
    LOG = "%{caster} поражает %{target} цепной молнией"
    EFFECT = ->(context, target) { context.damage!(target, amount: 3, type: :lightning, area: :chain) }
  end
end
