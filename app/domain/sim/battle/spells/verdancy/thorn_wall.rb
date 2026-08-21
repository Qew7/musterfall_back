module Sim::Battle::Spells::Verdancy
  class ThornWall
    extend Contract
    KEY = :thorn_wall
    NAME = "Thorn Wall"
    DESCRIPTION = "Raises a wall of grasping thorns."
    CASTING_VALUE = 11
    RANGE = 20
    TARGET_TYPE = :battlefield_point
    REQUIRES_LOS = true
    TEMPLATE = { shape: "circle", radius: 2.0 }
    SCORE_PROFILE = :terrain_block
    LOG = "%{caster} воздвигает стену шипов в точке %{target}"
    EFFECT = ->(context, target) { context.terrain!(:thorn_wall, at: target, duration: 3) }
  end
end
