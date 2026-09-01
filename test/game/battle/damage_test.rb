require "test_helper"

class SimBattleDamageTest < ActiveSupport::TestCase
  Attack = Sim::Battle::Phases::AttackResolution

  test "zero base power yields zero damage" do
    attacker = { melee: 0, abilities: [], weapon_type: "slash" }
    defender = { armor_type: "light", abilities: [] }

    assert_equal 0, Attack.damage(attacker, defender, "melee", "front", 1)
  end

  test "rear attacks deal more than front" do
    attacker = { melee: 4, abilities: [], weapon_type: "slash" }
    defender = { armor_type: "medium", abilities: [] }

    front = Attack.damage(attacker, defender, "melee", "front", 1)
    rear = Attack.damage(attacker, defender, "melee", "rear", 1)

    assert_operator rear, :>, front
  end

  test "damage is at least one when base power positive" do
    attacker = { melee: 1, abilities: [], weapon_type: "slash" }
    defender = { armor_type: "heavy", abilities: [] }

    assert_operator Attack.damage(attacker, defender, "melee", "front", 1), :>=, 1
  end

  test "charge boosts only a strike made after actual charge movement" do
    attacker = { melee: 6, abilities: [], weapon_type: "slash", charged_distance: 5 }
    defender = { armor_type: "medium", abilities: [] }

    charged = Attack.damage(attacker, defender, "melee", "front", 2)
    standing = Attack.damage(attacker.except(:charged_distance), defender, "melee", "front", 2)

    assert_operator charged, :>, standing
    assert_equal standing, Attack.damage(attacker.merge(charged_distance: 0), defender, "melee", "front", 2)
  end

  test "ferocious no longer adds flat melee damage" do
    attacker = { melee: 6, abilities: [ "ferocious" ], weapon_type: "slash" }
    defender = { armor_type: "medium", abilities: [] }

    boosted = Attack.damage(attacker, defender, "melee", "front", 2)
    plain = Attack.damage(attacker.merge(abilities: []), defender, "melee", "front", 2)

    assert_equal plain, boosted
  end

  test "resolute no longer reduces frontal damage" do
    attacker = { melee: 6, abilities: [], weapon_type: "slash" }
    defender = { armor_type: "medium", abilities: [ "resolute" ] }

    front = Attack.damage(attacker, defender, "melee", "front", 1)
    flank = Attack.damage(attacker, defender, "melee", "flank", 1)
    plain_front = Attack.damage(attacker, defender.merge(abilities: []), "melee", "front", 1)

    assert_equal plain_front, front
    assert_operator flank, :>, front
  end

  test "skirmisher ignores flank and rear facing bonus" do
    attacker = { melee: 6, abilities: [], weapon_type: "slash" }
    skirm = { armor_type: "light", abilities: [ "skirmisher" ] }
    ranked = { armor_type: "light", abilities: [] }

    assert_equal(
      Attack.damage(attacker, skirm, "melee", "front", 1),
      Attack.damage(attacker, skirm, "melee", "rear", 1)
    )
    assert_operator Attack.damage(attacker, ranked, "melee", "rear", 1), :>, Attack.damage(attacker, ranked, "melee", "front", 1)
  end

  test "machine boosts shooting damage" do
    attacker = { ranged: 7, abilities: [ "machine" ], weapon_type: "demolish" }
    defender = { armor_type: "heavy", abilities: [] }

    boosted = Attack.damage(attacker, defender, "shooting", "front", 1)
    plain = Attack.damage(attacker.merge(abilities: []), defender, "shooting", "front", 1)

    assert_operator boosted, :>=, plain
  end
end
