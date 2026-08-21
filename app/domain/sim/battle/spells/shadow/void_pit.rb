module Sim::Battle::Spells::Shadow
  class VoidPit
    extend Contract
    KEY = :void_pit
    NAME = "Void Pit"
    DESCRIPTION = "Opens a lethal void beneath a battlefield point."
    CASTING_VALUE = 13
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = true
    TEMPLATE = { shape: "circle", radius: 4.0 }
    SCORE_PROFILE = :area_damage
    LOG = "%{caster} разверзает яму пустоты под %{target}"
    EFFECT = ->(context, target) { context.damage!(target, amount: 5, type: :void, area: :burst) }
  end
end
