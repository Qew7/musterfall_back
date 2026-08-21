module Sim::Battle::Spells::Warcry
  class ChargeFrenzy
    extend Contract
    KEY = :charge_frenzy
    NAME = "Charge Frenzy"
    DESCRIPTION = "Whips an allied unit into a charging frenzy."
    CASTING_VALUE = 8
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :charge_buff
    LOG = "%{caster} гонит %{target} в атаку"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :charge_frenzy, duration: 1, value: 2) }
  end
end
