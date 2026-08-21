module Sim::Battle::Spells::Warcry
  class HurlingHand
    extend Contract
    KEY = :hurling_hand
    NAME = "Hurling Hand"
    DESCRIPTION = "Hurls an allied unit across the battlefield."
    CASTING_VALUE = 11
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = false
    SCORE_PROFILE = :mobility
    LOG = "%{caster} швыряет %{target} исполинской дланью"
    EFFECT = ->(context, target) { context.teleport!(target, to: context.destination_for(target, profile: :aggressive)) }
  end
end
