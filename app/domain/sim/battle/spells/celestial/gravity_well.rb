module Sim::Battle::Spells::Celestial
  class GravityWell
    extend Contract
    KEY = :gravity_well
    NAME = "Gravity Well"
    DESCRIPTION = "Pins enemies around a point under crushing gravity."
    CASTING_VALUE = 12
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = true
    TEMPLATE = { shape: "circle", radius: 4.0 }
    SCORE_PROFILE = :area_control
    LOG = "%{caster} создаёт колодец тяжести в точке %{target}"
    EFFECT = lambda do |context, target|
      context.terrain!(:gravity_well, at: target, duration: 2)
      context.add_effect!(target, key: :gravity_well, duration: 2, value: 2, area: :burst)
    end
  end
end
