module Sim::Battle::Spells::Verdancy
  class VerdantPath
    extend Contract
    KEY = :verdant_path
    NAME = "Verdant Path"
    DESCRIPTION = "Opens a swift living path for an allied unit."
    CASTING_VALUE = 12
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = false
    SCORE_PROFILE = :mobility
    LOG = "%{caster} открывает зелёный путь для %{target}"
    EFFECT = ->(context, target) { context.teleport!(target, to: context.destination_for(target, profile: :safe)) }
  end
end
