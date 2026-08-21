module Sim::Battle::Spells::Bestial
  class PrimalRoar
    extend Contract
    KEY = :primal_roar
    NAME = "Primal Roar"
    DESCRIPTION = "A supernatural roar shakes nearby enemies."
    CASTING_VALUE = 11
    TARGET_TYPE = :caster
    REQUIRES_LOS = false
    TEMPLATE = { shape: "aura", radius: 4.0 }
    SCORE_PROFILE = :enemy_aura_debuff
    LOG = "%{caster} сотрясает %{target} первобытным рёвом"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :primal_roar, duration: 1, value: 2, area: :aura) }
  end
end
