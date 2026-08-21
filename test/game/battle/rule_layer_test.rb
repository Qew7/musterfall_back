require "test_helper"
require_relative "../../support/rule_layer_lint"

class SimBattleRuleLayerTest < ActiveSupport::TestCase
  test "phases, facades, pathing and geometry do not inline rule policy" do
    hits = RuleLayerLint.scan(root: Rails.root.to_s)
    assert_empty RuleLayerLint.report(hits)
  end
end
