require "test_helper"

class SimCampaignAssignFactionTest < ActiveSupport::TestCase
  test "assigns faction and grants free hero" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    faction_id = catalog.factions.first[:id]
    result = Sim::Campaign::AssignFaction.call(
      campaign: campaign,
      catalog: catalog,
      player_id: "player-1",
      faction_id: faction_id
    )

    assert result.ok?
    player = result.value.find_player("player-1")
    assert_equal faction_id, player[:faction_id]
    assert_equal 1, player[:roster].count { |entity| entity[:kind] == "hero" }
    assert_equal 0, player[:roster].first.dig(:components, :economy, :cost)
  end

  test "unknown faction fails" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    result = Sim::Campaign::AssignFaction.call(
      campaign: campaign,
      catalog: catalog,
      player_id: "player-1",
      faction_id: "nope"
    )

    assert result.failure?
  end
end
