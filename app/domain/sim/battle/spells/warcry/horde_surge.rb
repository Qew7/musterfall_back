module Sim::Battle::Spells::Warcry
  class HordeSurge
    extend Contract
    KEY = :horde_surge
    NAME = "Horde Surge"
    DESCRIPTION = "Pushes nearby allies forward as one roaring mass."
    CASTING_VALUE = 12
    TARGET_TYPE = :caster
    REQUIRES_LOS = false
    TEMPLATE = { shape: "aura", radius: 4.0 }
    SCORE_PROFILE = :ally_aura_mobility
    LOG = "%{caster} поднимает натиск орды вокруг %{target}"
    EFFECT = ->(context, target) { context.move!(target, profile: :advance, distance: 3, area: :aura) }
  end
end
