module Sim::Battle::Spells::Necromancy
  class Withering
    extend Contract
    KEY = :withering
    NAME = "Withering"
    DESCRIPTION = "Withers an enemy unit over several rounds."
    CASTING_VALUE = 13
    TARGET_TYPE = :enemy_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :damage_over_time
    LOG = "%{caster} насылает увядание на %{target}"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :withering, duration: 3, value: 2) }
  end
end
