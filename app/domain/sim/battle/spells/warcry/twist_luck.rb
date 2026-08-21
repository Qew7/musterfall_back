module Sim::Battle::Spells::Warcry
  class TwistLuck
    extend Contract
    KEY = :twist_luck
    NAME = "Twist Luck"
    DESCRIPTION = "Twists luck against an enemy unit."
    CASTING_VALUE = 10
    TARGET_TYPE = :enemy_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :accuracy_debuff
    LOG = "%{caster} ломает удачу %{target}"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :twist_luck, duration: 1, value: 2) }
  end
end
