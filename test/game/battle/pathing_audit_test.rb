require "test_helper"

class SimBattlePathingAuditTest < ActiveSupport::TestCase
  test "audit report exposes reviewer scores and issue ids" do
    report = PathingAudit.report

    assert_kind_of Integer, report.linus
    assert_kind_of Integer, report.dijkstra
    assert_kind_of Integer, report.maneuver
    assert_operator report.linus, :>=, 0
    assert_operator report.dijkstra, :>=, 0
    assert_operator report.maneuver, :>=, 0
    assert_operator report.linus, :<=, 100
    report.issues.each do |issue|
      assert issue[:id], "issue missing id"
      assert issue[:message], "issue missing message"
      assert issue[:reviewers], "issue missing reviewers"
    end
  end

  test "invariants reject a plan that overlaps impassable terrain" do
    actor = BattleScenarios.combatant(x: 10.0, y: 12.0)
    house = BattleScenarios.terrain(x: 12.0, y: 12.0, width: 4.0, depth: 4.0)
    obstacle = Sim::Geometry::Battlefield.feature_as_obstacle(house)
    plan = { pose: { x: 12.0, y: 12.0, facing: 0.0 } }

    error = assert_raises(BattleInvariants::Violation) do
      BattleInvariants.verify_pathing_plan!(actor, plan, obstacles: [ obstacle ], budget: 8.0)
    end
    assert_includes error.message, "overlaps"
  end
end
