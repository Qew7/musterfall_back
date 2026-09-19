require "test_helper"

class BalanceArmyStageReportTest < ActiveSupport::TestCase
  test "groups stages and counts own appearances including both sides of a mirror" do
    version = CatalogVersion.current!
    scope = BalanceBattleRollup.where(catalog_version: version)
    scope.delete_all
    [
      { army_stage: "early", left_faction: "empire", right_faction: "greenskins", winner_id: "sim-left", left_army_cost: 500, right_army_cost: 450 },
      { army_stage: "late", left_faction: "empire", right_faction: "empire", winner_id: "sim-right", left_army_cost: 1000, right_army_cost: 900 },
      { left_faction: "empire", right_faction: "greenskins", winner_id: "sim-right", left_army_cost: 500, right_army_cost: 500 }
    ].each do |metrics|
      scope.create!(source: "synthetic", matchup_type: "bvb", metrics: metrics)
    end
    rows = Balance::ArmyStageReport.build(scope).index_by { |row| row[:stage] }
    assert_equal %w[early late legacy], rows.keys.sort
    assert_equal 475.0, rows["early"][:mean_army_cost]
    assert_equal({ appearances: 1, wins: 1, winrate: 1.0 }, rows["early"][:factions]["empire"])
    assert_equal({ appearances: 2, wins: 1, winrate: 0.5 }, rows["late"][:factions]["empire"])
  end
end
