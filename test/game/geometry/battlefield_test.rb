require "test_helper"

class SimGeometryBattlefieldTest < ActiveSupport::TestCase
  test "normalize facing wraps around" do
    assert_equal 10, Sim::Geometry::Battlefield.normalize_facing(370)
    assert_equal 350, Sim::Geometry::Battlefield.normalize_facing(-10)
  end

  test "classify attack vector" do
    defender = { x: 10, y: 10, facing: 0, base_width: 2, base_depth: 2 }
    front = { x: 14, y: 10 }
    rear = { x: 6, y: 10 }
    flank = { x: 10, y: 14 }

    assert_equal "front", Sim::Geometry::Battlefield.classify_attack_vector(front, defender)
    assert_equal "rear", Sim::Geometry::Battlefield.classify_attack_vector(rear, defender)
    assert_equal "flank", Sim::Geometry::Battlefield.classify_attack_vector(flank, defender)
  end

  test "clamp deployment stays in deployment depth" do
    position = Sim::Geometry::Battlefield.clamp_deployment_position(x: 99, y: -3, facing: 400)
    assert position[:x] < Sim::Geometry::Battlefield::CONFIG[:deployment_depth]
    assert_operator position[:y], :>=, 0
    assert_equal 40, position[:facing]
  end

  test "shortest facing delta picks the smaller arc" do
    assert_equal 90, Sim::Geometry::Battlefield.shortest_facing_delta(0, 90)
    assert_equal(-90, Sim::Geometry::Battlefield.shortest_facing_delta(0, 270))
    assert_in_delta 0, Sim::Geometry::Battlefield.shortest_facing_delta(10, 370), 0.001
  end

  test "wheel cost is outer-edge arc length" do
    unit = { facing: 0, base_width: 4, base_depth: 1 }
    expected_90 = (90 * Math::PI / 180.0) * 4
    assert_in_delta expected_90, Sim::Geometry::Battlefield.wheel_cost(unit, 0, 90), 0.001
    assert_in_delta 0.0, Sim::Geometry::Battlefield.wheel_cost(unit, 0, 0), 0.001
  end

  test "wheel cost matches distance travelled by the outer front corner" do
    unit = { x: 10, y: 10, facing: 0, base_width: 4, base_depth: 2 }
    delta = 45.0
    pivot = Sim::Geometry::Battlefield.wheel_pivot(unit, delta)
    corners = Sim::Geometry::Battlefield.unit_corners(unit)
    outer = delta.negative? ? corners[1] : corners[0]
    radius = Sim::Geometry::Battlefield.distance_between(pivot, outer)
    arc = (delta.abs * Math::PI / 180.0) * radius
    cost = Sim::Geometry::Battlefield.wheel_cost(unit, 0, delta)

    assert_in_delta 4.0, radius, 0.001
    assert_in_delta arc, cost, 0.001
  end

  test "apply wheel then remaining MV can march along the new facing" do
    # Spearmen width 4: a ~28.6° wheel costs 2", leaving 2" to march straight.
    unit = { x: 10, y: 12, facing: 0, base_width: 4, base_depth: 1, movement: 4 }
    wheel_budget = 2.0
    wheeled = Sim::Geometry::Battlefield.apply_wheel(unit, 90, wheel_budget)
    assert_in_delta 0.0, wheeled[:remaining], 0.05
    refute wheeled[:completed]
    assert_in_delta wheel_budget, wheeled[:cost], 0.05

    marched = Sim::Geometry::Battlefield.move_along_facing(
      unit.merge(x: wheeled[:x], y: wheeled[:y], facing: wheeled[:facing]),
      2.0
    )
    assert_in_delta 2.0, Sim::Geometry::Battlefield.distance_between(
      { x: wheeled[:x], y: wheeled[:y] },
      marched
    ), 0.05
  end

  test "apply wheel spends movement and can only partially turn" do
    unit = { x: 10, y: 10, facing: 0, base_width: 4, base_depth: 1 }
    full = Sim::Geometry::Battlefield.apply_wheel(unit, 90, 10)
    assert full[:completed]
    assert_equal 90, full[:facing]
    assert_in_delta 10 - Sim::Geometry::Battlefield.wheel_cost(unit, 0, 90), full[:remaining], 0.001
    refute_in_delta unit[:x], full[:x], 0.05
    refute_in_delta unit[:y], full[:y], 0.05

    partial = Sim::Geometry::Battlefield.apply_wheel(unit, 90, 3)
    refute partial[:completed]
    assert_in_delta 0.0, partial[:remaining], 0.001
    assert_operator partial[:facing], :>, 0
    assert_operator partial[:facing], :<, 90
  end

  test "wheel pose pivots on front corner so center travels an arc" do
    unit = { x: 0, y: 0, facing: 0, base_width: 2, base_depth: 2 }
    # +90° right wheel around front-right (1, 1) -> center (2, 0), facing 90
    pose = Sim::Geometry::Battlefield.wheel_pose(unit, 90)
    assert_in_delta 2.0, pose[:x], 0.001
    assert_in_delta 0.0, pose[:y], 0.001
    assert_in_delta 90.0, pose[:facing], 0.001

    left = Sim::Geometry::Battlefield.wheel_pose(unit, -90)
    assert_in_delta 2.0, left[:x], 0.001
    assert_in_delta 0.0, left[:y], 0.001
    assert_in_delta 270.0, left[:facing], 0.001
  end

  test "intermediate wheel poses keep the pivot front corner fixed" do
    unit = { x: 20.0, y: 12.0, facing: 0.0, base_width: 4.0, base_depth: 2.0 }
    [ -60.0, 45.0, 90.0 ].each do |delta|
      pivot = Sim::Geometry::Battlefield.wheel_pivot(unit, delta)
      8.times do |index|
        progress = (index + 1) / 8.0
        pose = Sim::Geometry::Battlefield.wheel_pose(unit, delta * progress)
        corners = Sim::Geometry::Battlefield.unit_corners(
          pose.merge(base_width: unit[:base_width], base_depth: unit[:base_depth])
        )
        pivoted_corner = delta.negative? ? corners[0] : corners[1]
        assert_in_delta pivot[:x], pivoted_corner[:x], 0.001, "delta=#{delta} t=#{progress}"
        assert_in_delta pivot[:y], pivoted_corner[:y], 0.001, "delta=#{delta} t=#{progress}"
      end
    end
  end
end
