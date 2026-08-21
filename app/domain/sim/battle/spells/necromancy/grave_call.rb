module Sim::Battle::Spells::Necromancy
  class GraveCall
    extend Contract
    KEY = :grave_call
    NAME = "Grave Call"
    DESCRIPTION = "Restores fallen models to an undead unit."
    CASTING_VALUE = 12
    TARGET_TYPE = :damaged_ally_unit
    REQUIRES_LOS = false
    SCORE_PROFILE = :resurrection
    SELECT_TARGETS = ->(_context, targets) {
      targets.select { |target| Array(target[:abilities]).include?("undead") }
    }
    LOG = "%{caster} обращает зов могилы к %{target}"
    EFFECT = ->(context, target) { context.resurrect!(target, models: 3) }
  end
end
