module Sim::Battle::Spells::Shadow
  class Miasma
    extend Contract
    KEY = :miasma
    NAME = "Miasma"
    DESCRIPTION = "Slows an enemy unit in clinging darkness."
    CASTING_VALUE = 8
    TARGET_TYPE = :enemy_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :movement_debuff
    LOG = "%{caster} окутывает %{target} миазмой"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :miasma, duration: 1, value: 2) }
  end
end
