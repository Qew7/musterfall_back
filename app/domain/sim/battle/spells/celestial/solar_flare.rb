module Sim::Battle::Spells::Celestial
  class SolarFlare
    extend Contract
    KEY = :solar_flare
    NAME = "Solar Flare"
    DESCRIPTION = "Blinds and scorches an exposed enemy unit."
    CASTING_VALUE = 10
    TARGET_TYPE = :enemy_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :damage_debuff
    LOG = "%{caster} обжигает %{target} солнечной вспышкой"
    EFFECT = lambda do |context, target|
      context.damage!(target, amount: 2, type: :radiant)
      context.add_effect!(target, key: :blinded, duration: 1, value: 1)
    end
  end
end
