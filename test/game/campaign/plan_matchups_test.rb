require "test_helper"

class SimCampaignPlanMatchupsTest < ActiveSupport::TestCase
  test "pairs last-round winners together and losers together" do
    campaign = Sim::Campaign::State.new(
      round: 2,
      last_round_report: {
        matchups: [
          { winner_id: "w1" },
          { winner_id: "w2" }
        ]
      },
      players: [ stub_player("w1"), stub_player("l1"), stub_player("w2"), stub_player("l2") ]
    )

    result = Sim::Campaign::PlanMatchups.call(campaign: campaign, catalog: nil, rng_seed: 1)
    pairs = result.value[:matchups].map { |matchup| [ matchup[:attacker][:id], matchup[:defender][:id] ] }

    assert_equal [ %w[w1 w2], %w[l1 l2] ], pairs
  end

  private

  def stub_player(id)
    {
      id: id,
      name: id,
      status: "active",
      roster: [ { kind: "unit", state: { current_health: 1 }, components: { formation: { row: "front" } } } ]
    }
  end
end
