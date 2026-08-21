module Sim::Battle::Spells::Ruin
  class WastingWind
    extend Contract
    KEY = :wasting_wind
    NAME = "Wasting Wind"
    DESCRIPTION = "Carries a wasting plague through enemy ranks."
    CASTING_VALUE = 13
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = true
    TEMPLATE = { shape: "line" }
    SCORE_PROFILE = :area_damage_over_time
    LOG = "%{caster} посылает ветер мора через %{target}"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :plague, duration: 3, value: 2, area: :line) }
  end
end
