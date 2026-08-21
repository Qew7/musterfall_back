module Sim::Battle::Spells::Celestial
  class Comet
    extend Contract
    KEY = :comet
    NAME = "Comet"
    DESCRIPTION = "Marks a point for a delayed celestial impact."
    CASTING_VALUE = 13
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = false
    TEMPLATE = { shape: "circle", radius: 2.5 }
    SCORE_PROFILE = :delayed_area_damage
    LOG = { success: "%{caster} призывает комету к %{target}", delayed: "Комета обрушивается на %{target}" }.freeze
    EFFECT = ->(context, target) { context.add_effect!(target, key: :comet, duration: 1, value: 5) }
  end
end
