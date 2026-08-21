module Sim::Battle::Spells::Celestial
  class Starlight
    extend Contract
    KEY = :starlight
    NAME = "Starlight"
    DESCRIPTION = "Bathes allies in steadying celestial light."
    CASTING_VALUE = 9
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :morale_buff
    LOG = "%{caster} озаряет %{target} звёздным светом"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :starlight, duration: 2, value: 2) }
  end
end
