require_relative "../../script/support/sim_boot"
require_relative "battle_scenarios"

# Executed in separate processes so Ruby and C cannot accidentally dispatch to
# the same implementation. Stable seeds include thin terrain and rotated trays.
rng = Random.new(812)
obb = Sim::Geometry::Obb
pathing = Sim::Battle::Pathing
results = 80.times.map do |index|
  mover = BattleScenarios.combatant(
    entity_id: "mover", x: 2.0 + rng.rand * 36, y: 2.0 + rng.rand * 20,
    facing: rng.rand * 720 - 180, base_width: 0.5 + rng.rand * 5, base_depth: 0.5 + rng.rand * 5
  )
  units = 4.times.map do |i|
    BattleScenarios.enemy(
      entity_id: "enemy-#{i}", x: rng.rand * 40, y: rng.rand * 24,
      facing: rng.rand * 360, base_width: 0.1 + rng.rand * 5, base_depth: 0.1 + rng.rand * 5
    )
  end
  terrain = [ BattleScenarios.terrain(id: "thin-wall", x: 20, y: 12, width: 0.1, depth: 8) ]
  world = pathing::Obstacles.merge([ mover, *units ], terrain)
  contact = index.even? ? units.first[:entity_id] : nil
  dests = 6.times.map { { x: rng.rand * 40, y: rng.rand * 24 } }
  {
    overlap: units.map { |unit| obb.overlap_units?(mover, unit) },
    distances: units.map { |unit| obb.distance_units(mover, unit) },
    blocker: world.first_blocker(mover, contact_id: contact)&.fetch(:entity_id),
    segments: dests.map { |to| world.segment_clear?(mover, mover, to, contact_id: contact) },
    batch: world.segments_open_mask(mover, mover, dests, contact).bytes,
    wheel: [ -90, 45, 90, 180 ].map { |delta| world.wheel_clear?(mover, mover[:facing] + delta, contact_id: contact) },
    vertices: world.route_points(mover, contact_id: contact).map { |p| [ p[:x].round(6), p[:y].round(6) ] }
  }
end
puts JSON.generate(native: obb.native?, queries: results)
