module Sim::Battle::Spells::Necromancy
  class RaiseDead
    extend Contract
    KEY = :raise_dead
    NAME = "Raise Dead"
    DESCRIPTION = "Raises a small unit of corpses from the ground."
    CASTING_VALUE = 10
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = true
    TEMPLATE = { shape: "circle", radius: 2.5 }
    SCORE_PROFILE = :summon
    LOG = "%{caster} поднимает мёртвых у %{target}"
    EFFECT = ->(context, target) { context.summon!(:zombies, near: target, count: 5) }
  end
end
