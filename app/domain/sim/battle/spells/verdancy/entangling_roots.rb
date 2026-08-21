module Sim::Battle::Spells::Verdancy
  class EntanglingRoots
    extend Contract
    KEY = :entangling_roots
    NAME = "Entangling Roots"
    DESCRIPTION = "Roots an enemy unit to the ground."
    CASTING_VALUE = 9
    TARGET_TYPE = :enemy_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :movement_debuff
    LOG = "%{caster} опутывает %{target} цепкими корнями"
    EFFECT = ->(context, target) {
      context.add_effect!(
        target,
        key: :entangled,
        duration: 1,
        modifiers: { movement: -target[:movement].to_f }
      )
    }
  end
end
