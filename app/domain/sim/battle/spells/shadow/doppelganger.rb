module Sim::Battle::Spells::Shadow
  class Doppelganger
    extend Contract
    KEY = :doppelganger
    NAME = "Doppelganger"
    DESCRIPTION = "Creates a shadow copy of an allied unit for 1d3+1 turns."
    CASTING_VALUE = 12
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :offense_buff
    SELECT_TARGETS = ->(_context, targets) { targets.reject { |target| target[:summoned] } }
    LOG = "%{caster} создаёт двойника для %{target}"
    EFFECT = ->(context, target) { context.clone_unit!(target) }
  end
end
