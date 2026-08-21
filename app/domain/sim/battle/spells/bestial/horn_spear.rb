module Sim::Battle::Spells::Bestial
  class HornSpear
    extend Contract
    KEY = :horn_spear
    NAME = "Horn Spear"
    DESCRIPTION = "Launches a piercing spear of hardened horn."
    CASTING_VALUE = 12
    TARGET_TYPE = :enemy_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :armor_piercing_damage
    LOG = "%{caster} пронзает %{target} роговым копьём"
    EFFECT = ->(context, target) { context.damage!(target, amount: 4, type: :puncture) }
  end
end
