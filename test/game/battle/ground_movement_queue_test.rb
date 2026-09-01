require "test_helper"

class SimBattleGroundMovementQueueTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  GM = Sim::Battle::Rules::Ground::Movement

  test "closer mover claims front before distant ally with better alignment" do
    orc = BattleScenarios.enemy(entity_id: "orc", x: 13, y: 8, facing: 0, base_width: 4, base_depth: 2)
    ghoul = BattleScenarios.combatant(
      entity_id: "ghoul",
      x: 21,
      y: 6,
      facing: 180,
      movement: 4,
      base_width: 4,
      base_depth: 2
    )
    skeleton = BattleScenarios.combatant(
      entity_id: "skel",
      x: 25,
      y: 8,
      facing: 180,
      movement: 3,
      base_width: 5,
      base_depth: 2
    )

    ghoul_dist = BF.distance_between_units(ghoul, orc)
    skel_dist = BF.distance_between_units(skeleton, orc)
    assert_operator ghoul_dist, :<, skel_dist
    align = ->(mover) { BF.angle_between(orc[:facing], orc, mover).to_f }
    assert_operator align.call(skeleton), :<, align.call(ghoul),
                    "old queue keyed on alignment; ghoul should still win on distance"

    claimed = Hash.new { |hash, key| hash[key] = {} }
    entries = GM.plan_entries([ skeleton, ghoul ], [ orc ], claimed)

    ghoul_entry = entries.find { |entry| entry[:combatant][:entity_id] == "ghoul" }
    assert_equal "orc", ghoul_entry[:nearest][:entity_id]
    assert_equal "front", ghoul_entry[:contact_slot]
    assert_equal "ghoul", claimed["orc"]["front"]
  end
end
