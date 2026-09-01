require "test_helper"

class BalanceTierReportTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    @version = CatalogVersion.current!
    @swords = ArmyTemplate.find_by!(template_key: "state_swords")
    @orcs = ArmyTemplate.find_by!(template_key: "orc_brutes")
  end

  test "build groups same-tier matchups and flags low sample" do
    BalanceDuelRun.create!(
      catalog_version: @version,
      left_template: @swords.template_key,
      right_template: @orcs.template_key,
      contact: "front",
      iterations: 6,
      left_wins: 3,
      right_wins: 3,
      left_winrate: 0.5,
      right_winrate: 0.5,
      avg_rounds: 4.0,
      config: {}
    )

    payload = Balance::TierReport.build(catalog_version_id: @version.id, contact: "front")

    assert_equal @version.id, payload[:catalog_version_id]
    assert_equal 1, payload[:by_tier]["line"][:pair_count]
    assert_equal 1, payload[:low_sample_pairs].length
    assert_includes payload[:by_tier]["line"][:unit_winrates].map { |row| row[:template_key] }, "state_swords"
  end
end
