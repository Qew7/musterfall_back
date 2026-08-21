module Sim::Battle::Spells::Ruin
  class Scorch
    extend Contract
    KEY = :scorch
    NAME = "Scorch"
    DESCRIPTION = "Burns a broad patch of ground with ruin-fire."
    CASTING_VALUE = 10
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = true
    TEMPLATE = { shape: "circle", radius: 4.0 }
    SCORE_PROFILE = :area_damage
    LOG = "%{caster} выжигает порчей %{target}"
    EFFECT = ->(context, target) { context.damage!(target, amount: 3, type: :fire, area: :burst) }
  end
end
