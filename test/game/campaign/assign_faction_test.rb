require "test_helper"

class SimCampaignAssignFactionTest < ActiveSupport::TestCase
  test "assigns faction and grants free hero" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    faction_id = catalog.factions.find do |faction|
      !catalog.hero_templates(faction[:id]).first&.dig(:abilities)&.include?("wizard")
    end[:id]
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

  test "starter hero follows seed order, not localized name sort" do
    assert_equal "captain_general", catalog.hero_templates("empire").first[:id]
    assert_equal "night_lord", catalog.hero_templates("undead").first[:id]
  end

  test "assigns a chosen starter hero from the faction pool" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    hero = catalog.hero_templates("empire").find { |entry| entry[:id] == "captain_general" }
    result = Sim::Campaign::AssignFaction.call(
      campaign: campaign,
      catalog: catalog,
      player_id: "player-1",
      faction_id: "empire",
      template_id: hero[:id]
    )

    assert result.ok?
    granted = result.value.find_player("player-1")[:roster].first
    assert_equal "captain_general", granted[:template_id]
  end

  test "rejects a starter from another faction" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    result = Sim::Campaign::AssignFaction.call(
      campaign: campaign,
      catalog: catalog,
      player_id: "player-1",
      faction_id: "empire",
      template_id: "war_chief"
    )

    assert_equal "starter hero is not in faction", result.error
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

  test "starter wizard requires a school and receives server-selected spells" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    faction_id = catalog.factions.find do |faction|
      catalog.hero_templates(faction[:id]).first&.dig(:abilities)&.include?("wizard")
    end[:id]

    with_spell_api(
      schools: %i[necromancy shadow],
      spell_keys: %i[raise_dead soul_drain grave_call]
    ) do
      missing = Sim::Campaign::AssignFaction.call(
        campaign: campaign,
        catalog: catalog,
        player_id: "player-1",
        faction_id: faction_id
      )
      assert_equal "magic school required", missing.error

      result = Sim::Campaign::AssignFaction.call(
        campaign: campaign,
        catalog: catalog,
        player_id: "player-1",
        faction_id: faction_id,
        school_key: "necromancy",
        rng: Sim::Rng::Seeded.new(9)
      )

      assert result.ok?
      hero = result.value.find_player("player-1")[:roster].first
      assert_equal "necromancy", hero.dig(:components, :hero, :magic_school)
      assert_equal 2, hero.dig(:components, :hero, :spell_keys).uniq.length
    end
  end
end
