require "test_helper"

class SimBattleStateTest < ActiveSupport::TestCase
  test "battlefield snapshot keeps the permanent combat profile" do
    unit = combatant(
      melee: 5,
      ranged: 2,
      spell: 1,
      skill: 4,
      armor_type: "heavy",
      weapon_type: "slash",
      abilities: %w[fear poison]
    )

    public_unit = Sim::Battle::State.snapshot_battlefield([ { combatants: [ unit ] } ]).first

    assert_equal 5, public_unit[:melee]
    assert_equal 2, public_unit[:ranged]
    assert_equal 1, public_unit[:spell]
    assert_equal 4, public_unit[:skill]
    assert_equal "heavy", public_unit[:armor_type]
    assert_equal "slash", public_unit[:weapon_type]
    assert_equal %w[fear poison], public_unit[:abilities]
    assert_empty public_unit[:spell_effects]
  end
end
