module Sim::Battle::Spells::Ruin
  class RiftLightning
    extend Contract
    KEY = :rift_lightning
    NAME = "Rift Lightning"
    DESCRIPTION = "Blasts an enemy with unstable rift energy."
    CASTING_VALUE = 8
    TARGET_TYPE = :enemy_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :direct_damage
    LOG = "%{caster} поражает %{target} молнией разлома"
    EFFECT = ->(context, target) { context.damage!(target, amount: 3, type: :chaos) }
  end
end
