require "test_helper"

class SimGeometryObbTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  Obb = Sim::Geometry::Obb
  Pathing = Sim::Battle::Pathing

  test "OBB overlap matches tray geometry for axis-aligned units" do
    left = BattleScenarios.combatant(x: 10.0, y: 12.0, facing: 0.0, base_width: 4.0, base_depth: 2.0)
    right = BattleScenarios.combatant(x: 11.5, y: 12.0, facing: 0.0, base_width: 4.0, base_depth: 2.0)

    assert BF.rectangles_overlap?(left, right)
    assert_in_delta 0.0, BF.distance_between_units(left, right), 0.0001
  end

  test "OBB distance is the gap between separated trays" do
    left = BattleScenarios.combatant(x: 8.0, y: 12.0, facing: 0.0, base_width: 4.0, base_depth: 2.0)
    right = BattleScenarios.combatant(x: 14.0, y: 12.0, facing: 0.0, base_width: 4.0, base_depth: 2.0)

    refute BF.rectangles_overlap?(left, right)
    assert_in_delta 4.0, BF.distance_between_units(left, right), 0.05
  end

  test "OBB distance keeps two decimal places" do
    left = BattleScenarios.combatant(x: 8.0, y: 12.0, facing: 0.0, base_width: 2.0, base_depth: 2.0)
    right = BattleScenarios.combatant(x: 8.0 + Math::PI, y: 12.0, facing: 0.0, base_width: 2.0, base_depth: 2.0)
    gap = BF.distance_between_units(left, right)

    assert_equal 1.14, gap
  end

  test "closest point on a facing-west tray sits on the front edge" do
    unit = BattleScenarios.combatant(x: 20.0, y: 10.0, facing: 180.0, base_width: 4.0, base_depth: 4.0)
    shore = BF.closest_point_on_unit({ x: 10.0, y: 10.0 }, unit)

    assert_in_delta 18.0, shore[:x], 0.05
    assert_in_delta 10.0, shore[:y], 0.05
  end

  test "90-degree trays keep the same gap after a facing swap" do
    north = BattleScenarios.combatant(x: 12.0, y: 12.0, facing: 90.0, base_width: 4.0, base_depth: 2.0)
    ahead = BattleScenarios.combatant(x: 12.0, y: 16.0, facing: 90.0, base_width: 2.0, base_depth: 2.0)

    refute BF.rectangles_overlap?(north, ahead)
    assert_in_delta 2.0, BF.distance_between_units(north, ahead), 0.05
  end

  test "front-left corner of a facing-east tray is south of the front-right corner" do
    unit = BattleScenarios.combatant(x: 10.0, y: 12.0, facing: 0.0, base_width: 4.0, base_depth: 2.0)
    corners = BF.unit_corners(unit)

    assert_in_delta 11.0, corners[0][:x], 0.0001
    assert_in_delta 10.0, corners[0][:y], 0.0001
    assert_in_delta 11.0, corners[1][:x], 0.0001
    assert_in_delta 14.0, corners[1][:y], 0.0001
  end

  test "charge target inside the contact band is not a first_blocker" do
    actor = BattleScenarios.combatant(x: 10.0, y: 12.0, facing: 0.0, base_width: 2.0, base_depth: 2.0)
    target = BattleScenarios.enemy(x: 12.3, y: 12.0, facing: 180.0, base_width: 2.0, base_depth: 2.0)
    obstacles = [ actor, target ]

    refute BF.rectangles_overlap?(actor, target)
    assert_operator BF.distance_between_units(actor, target), :<, Pathing::CONTACT
    assert_nil Pathing.first_blocker(actor, obstacles, contact_id: target[:entity_id])
    assert_equal target[:entity_id], Pathing.first_blocker(actor, obstacles)[:entity_id]
  end

  test "open aligned march is not truncated by a distant house" do
    actor = BattleScenarios.combatant(x: 6.0, y: 12.0, facing: 0.0, movement: 4.0)
    house = BattleScenarios.terrain(id: "house", x: 28.0, y: 12.0, width: 3.0, depth: 3.0)
    obstacles = Pathing.merge_obstacles([ actor ], [ house ])
    plan = Pathing.plan_approach(
      origin: actor,
      goal_point: { x: 20.0, y: 12.0 },
      budget: 4.0,
      obstacles: obstacles,
      bypass: false
    )

    assert plan[:pose]
    refute plan[:truncated]
    refute plan[:blocker]
    assert_in_delta 10.0, plan[:pose][:x], 0.2
  end

  test "native kernel agrees with the Ruby fallback when compiled" do
    skip "OBB C kernel not compiled (bin/rails sim:compile_obb)" unless Obb.native?

    args = [ 8.0, 12.0, 2.0, 1.0, 1.0, 0.0, 14.0, 12.0, 2.0, 1.0, 1.0, 0.0 ]
    assert_equal false, Obb::Native.overlap?(*args)
    assert_in_delta 4.0, Obb::Native.distance(*args), 0.0001
    assert_in_delta 4.0, Obb.distance(*args), 0.0001
  end
end
