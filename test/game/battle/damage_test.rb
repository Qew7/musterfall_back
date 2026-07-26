require "test_helper"

class SimBattleDamageTest < ActiveSupport::TestCase
  test "zero base power yields zero damage" do
    attacker = { melee: 0, abilities: [], weapon_type: "slash" }
    defender = { armor_type: "light", abilities: [] }

    assert_equal 0, Sim::Battle::Phases::AttackResolution.damage(attacker, defender, "melee", "front", 1)
  end

  test "rear attacks deal more than front" do
    attacker = { melee: 4, abilities: [], weapon_type: "slash" }
    defender = { armor_type: "medium", abilities: [] }

    front = Sim::Battle::Phases::AttackResolution.damage(attacker, defender, "melee", "front", 1)
    rear = Sim::Battle::Phases::AttackResolution.damage(attacker, defender, "melee", "rear", 1)

    assert_operator rear, :>, front
  end

  test "damage is at least one when base power positive" do
    attacker = { melee: 1, abilities: [], weapon_type: "slash" }
    defender = { armor_type: "heavy", abilities: [] }

    assert_operator Sim::Battle::Phases::AttackResolution.damage(attacker, defender, "melee", "front", 1), :>=, 1
  end
end
