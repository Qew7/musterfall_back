module Sim::Battle::Spells::Verdancy
  class Regrowth
    extend Contract
    KEY = :regrowth
    NAME = "Regrowth"
    DESCRIPTION = "Restores wounded models in an allied unit."
    CASTING_VALUE = 10
    TARGET_TYPE = :damaged_ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :healing
    LOG = "%{caster} пробуждает отрастание в %{target}"
    EFFECT = ->(context, target) { context.heal!(target, amount: 3) }
  end
end
