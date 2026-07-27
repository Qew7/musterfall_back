require "test_helper"

class SimBattlePathingRetreatTest < ActiveSupport::TestCase
  test "plan_retreat does not orbit an allied blocker on the nearest edge" do
    origin = {
      entity_id: "u1",
      name: "Бегущие",
      x: 20,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      current_health: 4,
      side_index: 0
    }
    ally = {
      entity_id: "ally-1",
      name: "Союзник",
      x: 8,
      y: 12,
      facing: 0,
      base_width: 6,
      base_depth: 4,
      current_health: 8,
      side_index: 0
    }

    plan = Sim::Battle::Pathing.plan_retreat(
      origin: origin,
      distance: 8,
      obstacles: [ ally ],
      ally_ids: [ ally[:entity_id] ]
    )

    refute plan[:avoided]
    assert plan[:pose]
    refute Sim::Geometry::Battlefield.rectangles_overlap?(
      origin.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing]),
      ally
    )
    assert_operator plan[:pose][:x], :>=, ally[:x] - 0.1
  end

  test "plan_retreat faces the run heading and does not orbit an enemy" do
    origin = {
      entity_id: "u1",
      name: "Бегущие",
      x: 20,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      current_health: 4,
      side_index: 0
    }
    enemy = {
      entity_id: "e1",
      name: "Враг",
      x: 8,
      y: 12,
      facing: 0,
      base_width: 4,
      base_depth: 4,
      current_health: 8,
      side_index: 1
    }

    plan = Sim::Battle::Pathing.plan_retreat(
      origin: origin,
      distance: 8,
      obstacles: [ enemy ],
      ally_ids: []
    )

    refute plan[:avoided]
    assert plan[:pose]
    assert_in_delta plan[:heading], plan[:pose][:facing], 0.001
    assert_operator Sim::Geometry::Battlefield.distance_between(origin, plan[:pose]), :>, 0.5
    refute Sim::Geometry::Battlefield.rectangles_overlap?(
      origin.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing]),
      enemy
    )
  end

  test "preferred flee heading is used and footprint does not overlap the threat" do
    origin = {
      entity_id: "unit-8",
      name: "Имперские мечники",
      x: 21.12,
      y: 11.41,
      facing: 176.7,
      base_width: 4,
      base_depth: 2,
      current_health: 5,
      side_index: 1,
      movement: 4
    }
    spawn = {
      entity_id: "unit-5",
      name: "Отродье Хаоса",
      x: 18.8,
      y: 11.6,
      facing: 356.7,
      base_width: 4,
      base_depth: 2,
      current_health: 8,
      side_index: 0
    }
    preferred = Sim::Geometry::Battlefield.heading_to(spawn, origin)

    plan = Sim::Battle::Pathing.plan_retreat(
      origin: origin,
      distance: 4,
      obstacles: [ spawn ],
      ally_ids: [],
      preferred_heading: preferred
    )

    assert plan[:pose]
    assert_in_delta plan[:heading], plan[:pose][:facing], 0.001
    assert_operator Sim::Geometry::Battlefield.distance_between(origin, plan[:pose]), :>, 1.0
    refute Sim::Geometry::Battlefield.rectangles_overlap?(
      origin.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing]),
      spawn
    )
    assert_operator(
      Sim::Geometry::Battlefield.distance_between_units(
        origin.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing]),
        spawn
      ),
      :>=,
      Sim::Battle::Pathing::CONTACT - 0.001
    )
  end
end
