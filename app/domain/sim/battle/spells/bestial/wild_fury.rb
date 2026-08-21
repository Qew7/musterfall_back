module Sim::Battle::Spells::Bestial
  class WildFury
    extend Contract
    KEY = :wild_fury
    NAME = "Wild Fury"
    DESCRIPTION = "Awakens predatory strength in an allied unit."
    CASTING_VALUE = 8
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :melee_buff
    # Prefer fighters; fall back to any legal ally if nobody has melee.
    SELECT_TARGETS = ->(_context, targets) {
      fighters = targets.select { |target| target[:melee].to_f.positive? }
      fighters.presence || targets
    }
    LOG = "%{caster} пробуждает дикую ярость в %{target}"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :wild_fury, duration: 1, value: 2) }
  end
end
