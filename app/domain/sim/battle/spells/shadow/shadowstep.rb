module Sim::Battle::Spells::Shadow
  class Shadowstep
    extend Contract
    KEY = :shadowstep
    NAME = "Shadowstep"
    DESCRIPTION = "Moves an allied unit between pools of darkness."
    CASTING_VALUE = 11
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = false
    SCORE_PROFILE = :mobility
    LOG = "%{caster} проводит %{target} шагом тени"
    EFFECT = ->(context, target) { context.teleport!(target, to: context.destination_for(target, profile: :flank)) }
  end
end
