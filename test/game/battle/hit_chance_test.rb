require "test_helper"

class SimBattleHitChanceTest < ActiveSupport::TestCase
  test "melee hit chance depends on relative skill" do
    stronger = Sim::Battle::Phases::AttackResolution.hit_chance({ skill: 5 }, { skill: 3 }, "melee")
    equal = Sim::Battle::Phases::AttackResolution.hit_chance({ skill: 3 }, { skill: 3 }, "melee")
    weaker = Sim::Battle::Phases::AttackResolution.hit_chance({ skill: 2 }, { skill: 4 }, "melee")

    assert_in_delta 5 / 6.0, stronger, 0.0001
    assert_in_delta 4 / 6.0, equal, 0.0001
    assert_in_delta 3 / 6.0, weaker, 0.0001
  end

  test "magic always hits" do
    assert_equal 1.0, Sim::Battle::Phases::AttackResolution.hit_chance({ skill: 1 }, { skill: 5 }, "magic")
  end

  test "hit uses rng" do
    rng = Sim::Rng::Seeded.new(1)
    attacker = { skill: 3 }
    defender = { skill: 3 }
    results = 40.times.map { Sim::Battle::Phases::AttackResolution.hit?(attacker, defender, "melee", rng) }

    assert_includes results, true
    assert_includes results, false
  end
end
