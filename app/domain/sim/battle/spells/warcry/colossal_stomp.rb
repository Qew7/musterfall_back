module Sim::Battle::Spells::Warcry
  class ColossalStomp
    extend Contract
    KEY = :colossal_stomp
    NAME = "Colossal Stomp"
    DESCRIPTION = "A colossal foot stomps an enemy formation."
    CASTING_VALUE = 13
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = false
    TEMPLATE = { shape: "circle", radius: 4.0 }
    SCORE_PROFILE = :area_damage
    LOG = "%{caster} обрушивает исполинскую стопу на %{target}"
    EFFECT = ->(context, target) { context.damage!(target, amount: 5, type: :impact, area: :burst) }
  end
end
