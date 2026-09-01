require "test_helper"

class BalanceCostAuditTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    @version = CatalogVersion.current!
  end

  test "build flags overcosted weak line unit" do
    BalanceDuelRun.create!(
      catalog_version: @version,
      left_template: "handgunners",
      right_template: "state_swords",
      contact: "front",
      iterations: 40,
      left_wins: 8,
      right_wins: 32,
      left_winrate: 0.2,
      right_winrate: 0.8,
      avg_rounds: 4.0,
      config: { "deploy" => "melee" }
    )

    payload = Balance::CostAudit.build(catalog_version_id: @version.id, deploy: "melee")
    row = payload[:by_tier]["line"][:rows].find { |entry| entry[:template_key] == "handgunners" }

    assert_not_nil row
    assert_includes %w[overcosted_weak underperformer fair low_sample], row[:verdict]
  end
end
