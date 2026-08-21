module Sim::Battle::Spells::Ruin
  class EarthSplit
    extend Contract
    KEY = :earth_split
    NAME = "Earth Split"
    DESCRIPTION = "Splits the earth in a jagged lethal line."
    CASTING_VALUE = 12
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = true
    TEMPLATE = { shape: "line" }
    SCORE_PROFILE = :line_damage
    LOG = "%{caster} раскалывает землю под %{target}"
    EFFECT = ->(context, target) { context.damage!(target, amount: 4, type: :earth, area: :line) }
  end
end
