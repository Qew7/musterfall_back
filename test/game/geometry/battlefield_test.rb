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
end
