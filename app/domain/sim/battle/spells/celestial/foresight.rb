module Sim::Battle::Spells::Celestial
  class Foresight
    extend Contract
    KEY = :foresight
    NAME = "Foresight"
    DESCRIPTION = "Reveals the enemy's next move to an allied unit."
    CASTING_VALUE = 8
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = false
    SCORE_PROFILE = :accuracy_buff
    LOG = "%{caster} дарует %{target} предвидение"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :foresight, duration: 1, value: 1) }
  end
end
