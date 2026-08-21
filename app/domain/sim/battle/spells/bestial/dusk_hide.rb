module Sim::Battle::Spells::Bestial
  class DuskHide
    extend Contract
    KEY = :dusk_hide
    NAME = "Dusk Hide"
    DESCRIPTION = "Shrouds allies in a spell-deflecting hide."
    CASTING_VALUE = 10
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :magic_defense
    LOG = "%{caster} укрывает %{target} шкурой сумерек"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :dusk_hide, duration: 2, value: 2) }
  end
end
