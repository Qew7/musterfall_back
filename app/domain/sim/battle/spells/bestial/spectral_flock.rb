module Sim::Battle::Spells::Bestial
  class SpectralFlock
    extend Contract
    KEY = :spectral_flock
    NAME = "Spectral Flock"
    DESCRIPTION = "A spectral flock tears into an enemy unit."
    CASTING_VALUE = 9
    TARGET_TYPE = :enemy_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :direct_damage
    LOG = "%{caster} насылает призрачную стаю на %{target}"
    EFFECT = ->(context, target) { context.damage!(target, amount: 2, type: :physical) }
  end
end
