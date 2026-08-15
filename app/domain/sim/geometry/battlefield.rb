module Sim
  module Geometry
    module Battlefield
      CONFIG = {
        width: 40,
        height: 24,
        deployment_depth: 10,
        front_arc_degrees: 120,
        contact_padding: 0.35,
        melee_contact_tolerance: 0.4,
        # Almost-touching band: closes the dead zone between "too close to march" and "not yet melee".
        contact_snap: 0.05,
        blast_radius: 1.6,
        volley_radius: 1.4,
        breath_length: 8.0,
        march_clearance_inches: 8.0,
        march_multiplier: 2.0
      }.freeze

      extend Core
      extend Wheel
      extend Turn
      extend Footprint
      extend Deployment
      extend Contact
      extend Align
      extend Targeting
      extend Templates
      extend Terrain
    end
  end
end
