require "test_helper"

class BalanceCompareVersionsTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    @from = CatalogVersion.current!
    @to = CatalogVersion.create!(
      content_hash: "compare-to-#{SecureRandom.hex(8)}",
      catalog_hash: @from.catalog_hash,
      rules_hash: @from.rules_hash
    )
  end

  test "build diffs template winrates between versions" do
    BalanceDuelRun.create!(
      catalog_version: @from,
      left_template: "state_swords",
      right_template: "orc_brutes",
      contact: "front",
      iterations: 40,
      left_wins: 20,
      right_wins: 20,
      left_winrate: 0.5,
      right_winrate: 0.5,
      avg_rounds: 4.0,
      config: { "deploy" => "melee" }
    )
    BalanceDuelRun.create!(
      catalog_version: @to,
      left_template: "state_swords",
      right_template: "orc_brutes",
      contact: "front",
      iterations: 40,
      left_wins: 32,
      right_wins: 8,
      left_winrate: 0.8,
      right_winrate: 0.2,
      avg_rounds: 4.0,
      config: { "deploy" => "melee" }
    )

    payload = Balance::CompareVersions.build(from_version_id: @from.id, to_version_id: @to.id, deploy: "melee")
    row = payload[:templates].find { |entry| entry[:template_key] == "state_swords" }

    assert_in_delta 0.3, row[:delta], 0.001
    assert row[:significant]
  end
end
