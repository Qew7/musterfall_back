module Sim::Battle::Spells::Bestial
  class HuntingPack
    extend Contract
    KEY = :hunting_pack
    NAME = "Hunting Pack"
    DESCRIPTION = "Summons spectral hounds beside the caster."
    CASTING_VALUE = 13
    TARGET_TYPE = :caster
    REQUIRES_LOS = false
    TEMPLATE = { shape: "aura", radius: 3.0 }
    SCORE_PROFILE = :summon
    LOG = "%{caster} призывает охотничью стаю к %{target}"
    EFFECT = ->(context, target) { context.summon!(:spectral_hounds, near: target) }
  end
end
