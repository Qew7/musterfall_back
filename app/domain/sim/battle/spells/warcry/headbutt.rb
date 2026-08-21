module Sim::Battle::Spells::Warcry
  class Headbutt
    extend Contract
    KEY = :headbutt
    NAME = "Headbutt"
    DESCRIPTION = "Crushes an enemy caster with raw force."
    CASTING_VALUE = 9
    TARGET_TYPE = :enemy_caster
    REQUIRES_LOS = true
    SCORE_PROFILE = :caster_damage
    LOG = "%{caster} бьёт %{target} башкой"
    EFFECT = ->(context, target) { context.damage!(target, amount: 3, type: :impact) }
  end
end
