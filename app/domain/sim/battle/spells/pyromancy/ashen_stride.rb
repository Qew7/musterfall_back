module Sim::Battle::Spells::Pyromancy
  class AshenStride
    extend Contract
    KEY = :ashen_stride
    NAME = "Ashen Stride"
    DESCRIPTION = "Carries an allied unit forward on a trail of embers."
    CASTING_VALUE = 12
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :mobility
    LOG = "%{caster} проводит %{target} пепельным шагом"
    EFFECT = ->(context, target) { context.teleport!(target, to: context.destination_for(target, profile: :advance)) }
  end
end
