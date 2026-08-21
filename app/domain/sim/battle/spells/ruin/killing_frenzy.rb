module Sim::Battle::Spells::Ruin
  class KillingFrenzy
    extend Contract
    KEY = :killing_frenzy
    NAME = "Killing Frenzy"
    DESCRIPTION = "Grants savage speed at the cost of mortal strain."
    CASTING_VALUE = 9
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :risky_offense_buff
    LOG = "%{caster} насылает боевое бешенство на %{target}"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :killing_frenzy, duration: 2, value: 3) }
  end
end
