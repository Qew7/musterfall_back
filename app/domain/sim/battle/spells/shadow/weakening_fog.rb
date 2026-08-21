module Sim::Battle::Spells::Shadow
  class WeakeningFog
    extend Contract
    KEY = :weakening_fog
    NAME = "Weakening Fog"
    DESCRIPTION = "Saps the striking power of enemies in an area."
    CASTING_VALUE = 10
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = true
    TEMPLATE = { shape: "circle", radius: 4.0 }
    SCORE_PROFILE = :area_attack_debuff
    LOG = "%{caster} напускает слабящий туман на %{target}"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :enfeebled, duration: 2, value: 2, area: :burst) }
  end
end
