module Sim::Battle::Spells::Shadow
  class CloakOfNight
    extend Contract
    KEY = :cloak_of_night
    NAME = "Cloak of Night"
    DESCRIPTION = "Conceals an allied unit from ranged attacks."
    CASTING_VALUE = 9
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :ranged_defense
    LOG = "%{caster} укрывает %{target} плащом ночи"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :cloak_of_night, duration: 2, value: 2) }
  end
end
