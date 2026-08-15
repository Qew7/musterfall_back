require "test_helper"

class SimGeometryBattlefieldTurnTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield

  test "turn right costs half of base MV, keeps the center, and swaps the tray onto the old flank" do
    unit = BattleScenarios.combatant(
      x: 8.0,
      y: 12.0,
      facing: 0.0,
      movement: 4.0,
      base_width: 5.0,
      base_depth: 2.0,
      files: 5,
      ranks: 2,
      frontage: 5
    )

    result = BF.apply_turn(unit, 90.0, 4.0)

    assert result[:completed]
    assert_in_delta 2.0, result[:cost], 0.001
    assert_in_delta 2.0, result[:remaining], 0.001
    assert_in_delta 8.0, result[:x], 0.001
    assert_in_delta 12.0, result[:y], 0.001
    assert_in_delta 90.0, result[:facing], 0.001
    assert_in_delta 2.0, result[:base_width], 0.001
    assert_in_delta 5.0, result[:base_depth], 0.001
    assert_equal 2, result[:files]
    assert_equal 5, result[:ranks]
    assert_equal 2, result[:frontage]
    assert_equal :turn, result[:kind]
  end

  test "turn left faces the old left flank" do
    unit = BattleScenarios.combatant(facing: 0.0, movement: 4.0, base_width: 5.0, base_depth: 2.0, files: 5, ranks: 2)
    result = BF.apply_turn(unit, 270.0, 4.0)

    assert result[:completed]
    assert_in_delta 270.0, result[:facing], 0.001
    assert_in_delta(-90.0, result[:delta], 0.001)
  end

  test "a 45 degree facing change is not a turn" do
    unit = BattleScenarios.combatant(facing: 0.0, movement: 4.0, base_width: 5.0, base_depth: 2.0, files: 5, ranks: 2)
    result = BF.apply_turn(unit, 45.0, 4.0)

    refute result[:completed]
    assert_in_delta 0.0, result[:cost], 0.001
    assert_in_delta 0.0, result[:facing], 0.001
  end

  test "turn does not spend more than half of base MV even with a larger remaining budget" do
    unit = BattleScenarios.combatant(facing: 0.0, movement: 4.0, base_width: 5.0, base_depth: 2.0, files: 5, ranks: 2)
    result = BF.apply_turn(unit, 90.0, 8.0)

    assert_in_delta 2.0, result[:cost], 0.001
    assert_in_delta 6.0, result[:remaining], 0.001
  end
end
