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

    # May switch to another edge's straight run, but never mark an ally-orbit bypass.
    refute plan[:avoided]
    assert plan[:pose]
    refute Sim::Geometry::Battlefield.rectangles_overlap?(
      origin.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing]),
      ally
    )
    # Must not slip past the ally westward via a flank slide.
    assert_operator plan[:pose][:x], :>=, ally[:x] - 0.1
  end

  test "plan_retreat may still bypass an enemy blocker" do
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

    refute plan[:blocked_by_ally]
    assert plan[:pose]
    assert_operator Sim::Geometry::Battlefield.distance_between(origin, plan[:pose]), :>, 0.5
  end
end
