module Sim::Battle::Spells::Verdancy
  class Oakheart
    extend Contract
    KEY = :oakheart
    NAME = "Oakheart"
    DESCRIPTION = "Hardens allied flesh like ancient timber."
    CASTING_VALUE = 8
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :armor_buff
    LOG = "%{caster} дарует %{target} дубовое сердце"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :oakheart, duration: 2, value: 2) }
  end
end
