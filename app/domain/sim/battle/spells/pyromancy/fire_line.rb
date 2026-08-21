module Sim::Battle::Spells::Pyromancy
  class FireLine
    extend Contract
    KEY = :fire_line
    NAME = "Fire Line"
    DESCRIPTION = "Drives a line of fire through enemy ranks."
    CASTING_VALUE = 11
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = true
    TEMPLATE = { shape: "line" }
    SCORE_PROFILE = :line_damage
    LOG = "%{caster} проводит огненную черту сквозь %{target}"
    EFFECT = ->(context, target) { context.damage!(target, amount: 2, type: :fire, area: :line) }
  end
end
