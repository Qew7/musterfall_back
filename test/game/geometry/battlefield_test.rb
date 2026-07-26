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
end
