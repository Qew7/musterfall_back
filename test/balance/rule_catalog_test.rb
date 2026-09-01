# frozen_string_literal: true

require "test_helper"

class BalanceRuleCatalogTest < ActiveSupport::TestCase
  test "scan finds rule headers in battle rule files" do
    entries = Balance::RuleCatalog.scan
    assert entries.length >= 50, "expected annotated rule files, got #{entries.length}"
    assert entries.all? { |row| row[:key].present? && row[:phase].present? && row[:concept].present? }
  end

  test "for_abilities maps camelCase ability keys" do
    rows = Balance::RuleCatalog.for_abilities(%w[shieldwall fear poison])
    assert rows.key?("shieldwall")
    assert rows.key?("fear")
    assert rows["fear"].length >= 3
  end

  test "concept describes rule without duel-specific suffix" do
    entry = Balance::RuleCatalog.scan.find { |row| row[:key] == "shieldwall" }
    assert entry
    assert_includes entry[:concept], "×0.75"
    assert_not entry[:concept].match?(/Balance:/i)
  end
end
