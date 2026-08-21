module Sim::Battle::Spells::Pyromancy
  class Inferno
    extend Contract
    KEY = :inferno
    NAME = "Inferno"
    DESCRIPTION = "Engulfs an area in an intense firestorm."
    CASTING_VALUE = 13
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = true
    TEMPLATE = { shape: "circle", radius: 4.0 }
    SCORE_PROFILE = :area_damage
    LOG = "%{caster} разжигает инферно в точке %{target}"
    EFFECT = ->(context, target) { context.damage!(target, amount: 4, type: :fire, area: :burst) }
  end
end
