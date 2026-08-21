module Sim::Battle::Spells::Ruin
  class HowlingGale
    extend Contract
    KEY = :howling_gale
    NAME = "Howling Gale"
    DESCRIPTION = "Fills the field with winds that hinder flight and missiles."
    CASTING_VALUE = 11
    TARGET_TYPE = :battlefield
    REQUIRES_LOS = false
    SCORE_PROFILE = :global_ranged_control
    LOG = "%{caster} поднимает вой бури над %{target}"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :howling_gale, duration: 2, value: 2) }
  end
end
