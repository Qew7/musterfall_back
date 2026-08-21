module Sim::Battle::Spells::Pyromancy
  class CinderShield
    extend Contract
    KEY = :cinder_shield
    NAME = "Cinder Shield"
    DESCRIPTION = "Wraps an allied unit in retaliatory embers."
    CASTING_VALUE = 9
    TARGET_TYPE = :ally_unit
    REQUIRES_LOS = true
    SCORE_PROFILE = :defensive_buff
    LOG = "%{caster} окутывает %{target} щитом раскалённых углей"
    EFFECT = ->(context, target) { context.add_effect!(target, key: :cinder_shield, duration: 1, value: 2) }
  end
end
