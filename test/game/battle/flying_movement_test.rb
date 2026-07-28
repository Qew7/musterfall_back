require "test_helper"

class SimBattleFlyingMovementTest < ActiveSupport::TestCase
  test "truncated flyer leap faces target enemy at landing" do
    enemy = {
      entity_id: "unit-11", x: 35.0, y: 19.0, facing: 180.0,
      base_width: 4, base_depth: 4, files: 2, ranks: 2, models_remaining: 4,
      side_index: 1, is_routing: false, movement: 4
    }
    dragon = {
      entity_id: "unit-33", x: 12.86708584166788, y: 13.145196668627735, facing: 14.817022315357974,
      base_width: 4, base_depth: 4, files: 1, ranks: 1, models_remaining: 1,
      side_index: 0, side_key: "left", movement: 5, abilities: [ "flying" ]
    }

    intent = Sim::Battle::Rules::Flying::Movement.build_closing_intent(
      dragon, enemy, [ enemy ], "rear", 5.0, :flyer_approach
    )

    assert intent, "expected a closing intent"
    destination = intent[:destination]
    expected_facing = Sim::Geometry::Battlefield.heading_to(destination, enemy)

    assert intent[:plan][:truncated], "expected truncated leap toward rear setup"
    assert Sim::Geometry::Battlefield.in_front_arc?(destination, enemy, destination[:facing]),
           "flyer should face target after landing"
    assert_in_delta expected_facing, destination[:facing], 0.05
    refute_in_delta 180.0, destination[:facing], 5.0,
                     "should not keep rear-goal facing while still in front arc"
  end

  test "ranged-primary flyers use flying movement instead of reposition hold" do
    dragon = {
      entity_id: "unit-33", name: "Костяной дракон", kind: "unit",
      x: 8.0, y: 20.0, facing: 0.0, lane: "right", row: "front",
      base_width: 2, base_depth: 2, files: 1, ranks: 1, models_remaining: 1,
      side_key: "left", side_index: 0, movement: 20, melee: 3, ranged: 4, spell: 0,
      current_health: 8, is_routing: false, initiative: 4,
      abilities: %w[flying monster ranged fear undead]
    }

    refute Sim::Battle::Decisions::Roles.melee_primary?(dragon)
    assert Sim::Battle::Decisions::Movement.flying?(dragon)
    assert_includes Sim::Battle::Decisions::Movement.melee_movers([ dragon ]), dragon

    enemy = {
      entity_id: "unit-10", name: "Аркебузиры", kind: "unit",
      x: 31.0, y: 3.0, facing: 180.0, lane: "right", row: "front",
      base_width: 5, base_depth: 2, files: 5, ranks: 2, models_remaining: 10,
      side_key: "right", side_index: 1, movement: 3, melee: 2, ranged: 5, spell: 0,
      current_health: 10, is_routing: false, shooting_range: 9, requires_line_of_sight: true
    }
    claimed = Hash.new { |hash, key| hash[key] = {} }

    entry = Sim::Battle::Rules::Flying::Movement.plan_entry(dragon, [ enemy ], claimed, [])
    assert entry, "expected flying assault plan for ranged-primary dragon"
    assert_equal :flyer_approach, entry[:approach_mode]
  end
end
