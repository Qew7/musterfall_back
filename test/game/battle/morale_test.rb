require "test_helper"

class SimBattleMoraleTest < ActiveSupport::TestCase
  test "deterministic dice from seed string" do
    assert_equal Sim::Battle::Phases::Morale.roll_dice("melee:1:0:unit-1"), Sim::Battle::Phases::Morale.roll_dice("melee:1:0:unit-1")
    assert_operator Sim::Battle::Phases::Morale.roll_dice("a"), :>=, 2
    assert_operator Sim::Battle::Phases::Morale.roll_dice("a"), :<=, 12
  end

  test "fear and combat score reduce threshold" do
    combatant = { entity_id: "u1", name: "Spearmen", kind: "unit", morale: 7, abilities: [], x: 5, y: 5 }
    allies = [ combatant ]
    enemies = [ { abilities: [ "fear" ], x: 6, y: 5 } ]
    check = Sim::Battle::Phases::Morale.resolve_check(
      combatant: combatant,
      allies: allies,
      enemies: enemies,
      round_number: 1,
      phase_type: "melee",
      combat_score_delta: 2,
      sequence: 0
    )

    assert_equal 4, check[:threshold]
  end
end
