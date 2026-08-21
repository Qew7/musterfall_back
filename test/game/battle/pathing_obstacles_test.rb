require "test_helper"

class SimBattlePathingObstaclesTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  Obstacles = Sim::Battle::Pathing::Obstacles

  test "merge keeps living units and impassable terrain, drops difficult ground" do
    actor = BattleScenarios.combatant(entity_id: "a", x: 6.0, y: 12.0)
    dead = BattleScenarios.combatant(entity_id: "dead", x: 10.0, y: 12.0, current_health: 0)
    lake = BattleScenarios.terrain(id: "lake", type: "lake", x: 16.0, y: 12.0, impassable: true)
    mud = BattleScenarios.terrain(id: "mud", type: "difficult", x: 20.0, y: 12.0, impassable: false)

    world = Obstacles.merge([ actor, dead ], [ lake, mud ])

    assert_equal [ "a", "lake" ].sort, world.map { |entry| entry[:entity_id] }.sort
    assert_equal world.size, world.kernels.size
  end

  test "around drops the mover and answers first_blocker for everyone else" do
    mover = BattleScenarios.combatant(entity_id: "mover", x: 8.0, y: 12.0, base_width: 4.0, base_depth: 4.0)
    ally = BattleScenarios.combatant(entity_id: "ally", x: 14.0, y: 12.0, base_width: 4.0, base_depth: 4.0)
    lake = BattleScenarios.terrain(id: "lake", type: "lake", x: 16.0, y: 12.0, width: 5.0, depth: 3.5)

    world = Obstacles.around(mover, units: [ mover, ally ], terrain: [ lake ])
    refute world.any? { |entry| entry[:entity_id] == "mover" }

    overlap = mover.merge(x: 14.0, y: 12.0)
    assert_equal "ally", world.first_blocker(overlap)[:entity_id]

    into_lake = mover.merge(x: 16.0, y: 12.0)
    assert_equal "lake", world.except(ally[:entity_id]).first_blocker(into_lake)[:entity_id]
  end

  test "contact_pose keeps a free charge dest and finds another when the dest is occupied" do
    mover = BattleScenarios.combatant(entity_id: "mover", x: 8.0, y: 12.0, base_width: 4.0, base_depth: 4.0)
    enemy = BattleScenarios.enemy(x: 22.0, y: 12.0, base_width: 2.0, base_depth: 2.0)
    world = Obstacles.merge([ mover, enemy ], [])
    dest = world.contact_pose(mover, enemy, contact_id: enemy[:entity_id])

    assert dest
    refute BF.rectangles_overlap?(mover.merge(x: dest[:x], y: dest[:y]), enemy)
  end

  test "except removes the contact so the thread can end on the claimed face" do
    enemy = BattleScenarios.enemy(x: 22.0, y: 12.0)
    lake = BattleScenarios.terrain(id: "lake", type: "lake", x: 16.0, y: 12.0)
    world = Obstacles.merge([ enemy ], [ lake ]).except(enemy[:entity_id])

    assert_equal [ "lake" ], world.map { |entry| entry[:entity_id] }
  end

  test "wheel_fits is false when the arc costs more than the budget at this width" do
    mover = BattleScenarios.combatant(
      entity_id: "mover", x: 20.0, y: 12.0, facing: 0.0,
      base_width: 5.0, base_depth: 2.0, movement: 3.0
    )
    world = Obstacles.merge([ mover ], [])

    refute world.wheel_fits?(mover, 90.0, 3.0)
    assert world.wheel_fits?(mover, 20.0, 3.0)
  end

  test "wheel_clear is false when the swinging tray hits a friend" do
    mover = BattleScenarios.combatant(
      entity_id: "mover", x: 35.0, y: 19.0, facing: 180.0,
      base_width: 4.0, base_depth: 4.0
    )
    friend = BattleScenarios.combatant(
      entity_id: "hero-2", x: 31.0, y: 19.0, facing: 180.0,
      base_width: 1.0, base_depth: 1.0
    )
    world = Obstacles.merge([ mover, friend ], [])

    refute world.wheel_clear?(mover, 270.0)
  end

  test "wrap vertices sit outside the tray circumradius so corners clear the obstacle" do
    mover = BattleScenarios.combatant(
      x: 8.0, y: 12.0, facing: 0.0, base_width: 5.0, base_depth: 4.0
    )
    lake = BattleScenarios.terrain(id: "lake", type: "lake", x: 16.0, y: 12.0, width: 3.0, depth: 2.4)
    world = Obstacles.merge([ mover ], [ lake ])
    lake_obs = BF.feature_as_obstacle(lake)
    vertices = world.wrap_vertices(mover)

    assert vertices.any?, "expected Minkowski wrap vertices around the lake"
    vertices.each do |vertex|
      pose = mover.merge(x: vertex[:x], y: vertex[:y])
      refute BF.rectangles_overlap?(pose, lake_obs), vertex.inspect
    end

    corners = vertices.select { |vertex| (vertex[:x] - 16.0).abs > 2.0 && (vertex[:y] - 12.0).abs > 2.0 }
    assert corners.any?, "expected hypot-offset corners, got #{vertices.inspect}"
    corners.each do |vertex|
      heading = BF.heading_to(mover, vertex)
      pose = mover.merge(x: vertex[:x], y: vertex[:y], facing: heading)
      refute BF.rectangles_overlap?(pose, lake_obs), vertex.inspect
    end
  end

  test "wrap_vertices omit a vertex whose tray hangs off the board" do
    mover = BattleScenarios.combatant(
      entity_id: "unit-36", x: 4.0, y: 4.0, facing: 0.0,
      base_width: 4.0, base_depth: 4.0
    )
    mage = BattleScenarios.combatant(entity_id: "hero-1", x: 8.0, y: 4.0, base_width: 1.0, base_depth: 1.0)
    world = Obstacles.merge([ mover, mage ], [])
    vertices = world.wrap_vertices(mover)

    refute vertices.any? { |vertex| vertex[:y] < 1.5 }, vertices.inspect
    assert vertices.any? { |vertex| vertex[:y] > mover[:y] + 1.0 }, vertices.inspect
  end
end
