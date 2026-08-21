module Sim::Battle::Spells::Necromancy
  class DeathlyVigor
    extend Contract
    KEY = :deathly_vigor
    NAME = "Deathly Vigor"
    DESCRIPTION = "Fills an allied unit with tireless deathly force."
    CASTING_VALUE = 11
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :offense_buff
    LOG = "%{caster} наполняет %{target} мёртвой бодростью"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :deathly_vigor, duration: 2, value: 2) }
  end
end
