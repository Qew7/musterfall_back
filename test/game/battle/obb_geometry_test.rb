require "sim_test_helper"

class SimGeometryObbTest < SimTestCase
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

  test "native blocker_index matches Ruby first_blocker" do
    skip "OBB C kernel not compiled (bin/rails sim:compile_obb)" unless Obb.native?

    actor = BattleScenarios.combatant(x: 10.0, y: 12.0, facing: 0.0, base_width: 2.0, base_depth: 2.0)
    target = BattleScenarios.enemy(x: 12.3, y: 12.0, facing: 180.0, base_width: 2.0, base_depth: 2.0)
    world = Pathing::Obstacles.new([ actor, target ])

    assert_nil world.first_blocker(actor, contact_id: target[:entity_id])
    assert_equal target[:entity_id], world.first_blocker(actor)[:entity_id]
  end

  test "matchup 679 kamikaze dest is blocked when allied goblins are in the world" do
    # Stored clip: unit-10 (5,16)->(6.96,15.96) ∩ unit-21 (8,13) 5x3. C/Ruby both see it.
    actor = BattleScenarios.combatant(
      entity_id: "unit-10", x: 5.0, y: 16.0, facing: 0.0, base_width: 2.0, base_depth: 2.0
    )
    ally = BattleScenarios.combatant(
      entity_id: "unit-21", x: 8.0, y: 13.0, facing: 0.0, base_width: 5.0, base_depth: 3.0
    )
    dest = actor.merge(x: 6.96, y: 15.96, facing: 357.7)
    world = Pathing::Obstacles.new([ actor, ally ])
    empty = Pathing::Obstacles.new([ actor ])

    assert Obb.overlap_units?(dest, ally)
    assert_in_delta 0.5, Obb.distance_units(actor, ally), 0.05
    assert_equal "unit-21", world.first_blocker(dest)[:entity_id]
    refute world.segment_clear?(actor, { x: 5.0, y: 16.0 }, { x: 6.96, y: 15.96 })
    assert empty.segment_clear?(actor, { x: 5.0, y: 16.0 }, { x: 6.96, y: 15.96 })
  end

  test "native segment_clear matches Ruby translation of a short hop" do
    skip "OBB C kernel not compiled (bin/rails sim:compile_obb)" unless Obb.native?

    actor = BattleScenarios.combatant(x: 8.0, y: 12.0, facing: 0.0, base_width: 2.0, base_depth: 2.0)
    blocker = BattleScenarios.enemy(x: 20.0, y: 12.0, facing: 180.0, base_width: 4.0, base_depth: 4.0)
    world = Pathing::Obstacles.new([ actor, blocker ])
    from = { x: 8.0, y: 12.0 }
    open_to = { x: 12.0, y: 12.0 }
    blocked_to = { x: 20.0, y: 12.0 }

    assert world.segment_clear?(actor, from, open_to)
    refute world.segment_clear?(actor, from, blocked_to)
  end

  test "native wheel_clear matches the sampled Ruby wheel" do
    skip "OBB C kernel not compiled (bin/rails sim:compile_obb)" unless Obb.native?

    actor = BattleScenarios.combatant(x: 10.0, y: 12.0, facing: 0.0, base_width: 4.0, base_depth: 2.0)
    house = BattleScenarios.terrain(id: "house", x: 12.5, y: 14.0, width: 3.0, depth: 3.0)
    world = Pathing::Obstacles.merge([ actor ], [ house ])

    [ 0.0, 45.0, 90.0, 135.0, -90.0, 180.0 ].each do |heading|
      assert_equal ruby_wheel_clear?(world, actor, heading), world.wheel_clear?(actor, heading), heading
    end
  end

  test "native route_points match the Ruby wrap vertices" do
    skip "OBB C kernel not compiled (bin/rails sim:compile_obb)" unless Obb.native?

    actor = BattleScenarios.combatant(
      entity_id: "unit-1", x: 8.0, y: 10.0, facing: 20.0, base_width: 4.0, base_depth: 2.0
    )
    ally = BattleScenarios.combatant(
      entity_id: "unit-2", x: 16.0, y: 12.0, facing: 180.0, base_width: 5.0, base_depth: 3.0
    )
    house = BattleScenarios.terrain(id: "house", x: 22.0, y: 8.0, width: 3.0, depth: 4.0)
    world = Pathing::Obstacles.merge([ actor, ally ], [ house ])

    assert_equal ruby_route_points(world, actor), world.route_points(actor)
    assert_equal ruby_route_points(world, actor, "unit-2"), world.route_points(actor, contact_id: "unit-2")
  end

  test "native kernel is restored if Zeitwerk unloaded Native" do
    skip "OBB C kernel not compiled (bin/rails sim:compile_obb)" unless Obb.native?

    Obb.send(:remove_const, :Native)
    silence_warnings { load File.expand_path("../../../app/domain/sim/geometry/obb.rb", __dir__) }

    assert Obb.native?
    assert Obb::Native.respond_to?(:segments_clear)
  end

  test "tray_on_battlefield matches corner containment" do
    rng = Random.new(1)
    width = BF::CONFIG[:width].to_f
    height = BF::CONFIG[:height].to_f
    eps = 1.0e-6

    200.times do
      pose = {
        x: (rng.rand * 50) - 5,
        y: (rng.rand * 34) - 5,
        facing: rng.rand * 360,
        base_width: (rng.rand * 8) + 0.1,
        base_depth: (rng.rand * 8) + 0.1
      }
      by_corners = BF.unit_corners(pose).all? do |corner|
        corner[:x].between?(-eps, width + eps) && corner[:y].between?(-eps, height + eps)
      end

      assert_equal by_corners, BF.tray_on_battlefield?(pose), pose.inspect
    end
  end

  def ruby_wheel_clear?(world, mover, heading)
    delta = BF.shortest_facing_delta(mover[:facing], heading)
    return true if delta.abs <= 0.05

    steps = [ [ 8, (delta.abs / 10).ceil ].max, 20 ].min
    steps.times do |index|
      pose = BF.wheel_pose(mover, delta * ((index + 1).to_f / steps))
      return false if world.first_blocker(mover, x: pose[:x], y: pose[:y], facing: pose[:facing])
    end
    true
  end

  def ruby_route_points(world, mover, contact_id = nil)
    seen = {}
    world.kernels.filter_map do |kernel|
      next if kernel.id == mover[:entity_id]
      next if contact_id && kernel.id == contact_id

      world.send(:minkowski_points, mover, kernel).filter_map do |vertex|
        pose = BF.fit_tray_on_battlefield(mover.merge(x: vertex[:x], y: vertex[:y]))
        next unless pose
        next unless world.clear?(pose, contact_id: contact_id)

        key = [ pose[:x].round(2), pose[:y].round(2) ]
        next if seen[key]

        seen[key] = true
        { x: pose[:x], y: pose[:y] }
      end
    end.flatten
  end
end
