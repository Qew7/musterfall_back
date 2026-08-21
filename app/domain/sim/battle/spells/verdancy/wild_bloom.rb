module Sim::Battle::Spells::Verdancy
  class WildBloom
    extend Contract
    KEY = :wild_bloom
    NAME = "Wild Bloom"
    DESCRIPTION = "Fills an area with healing life."
    CASTING_VALUE = 13
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = true
    TEMPLATE = { shape: "circle", radius: 4.0 }
    SCORE_PROFILE = :area_healing
    LOG = "%{caster} вызывает дикий цвет в точке %{target}"
    EFFECT = ->(context, target) { context.heal!(target, amount: 2, area: :burst) }
  end
end
