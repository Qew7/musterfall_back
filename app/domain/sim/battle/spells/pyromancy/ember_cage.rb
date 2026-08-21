module Sim::Battle::Spells::Pyromancy
  class EmberCage
    extend Contract
    KEY = :ember_cage
    NAME = "Ember Cage"
    DESCRIPTION = "Punishes an enemy unit when it moves."
    CASTING_VALUE = 10
    TARGET_TYPE = :enemy_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :movement_hex
    LOG = "%{caster} замыкает %{target} в клетке углей"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :ember_cage, duration: 1, value: 3) }
  end
end
