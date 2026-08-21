module Sim::Battle::Spells::Necromancy
  class GraveDance
    extend Contract
    KEY = :grave_dance
    NAME = "Grave Dance"
    DESCRIPTION = "Drives an allied unit forward with unnatural speed."
    CASTING_VALUE = 8
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :mobility
    LOG = "%{caster} увлекает %{target} в пляску мертвецов"
    EFFECT = ->(context, target) { context.move!(target, profile: :advance, distance: 4) }
  end
end
