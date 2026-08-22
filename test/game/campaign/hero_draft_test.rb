require "test_helper"

class SimCampaignHeroDraftTest < ActiveSupport::TestCase
  setup do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    @campaign = Sim::Campaign::AssignFaction.call(
      campaign: campaign,
      catalog: catalog,
      player_id: "player-1",
      faction_id: catalog.factions.first[:id],
      school_key: starter_school_key(catalog.factions.first[:id])
    ).value
    @hero = @campaign.find_player("player-1")[:roster].find { |entity| entity[:kind] == "hero" }
  end

  test "prepare fails when hero is not ready" do
    result = Sim::Campaign::HeroDraft.prepare(
      campaign: @campaign,
      catalog: catalog,
      player_id: "player-1",
      hero_id: @hero[:id],
      rng: Sim::Rng::Seeded.new(1)
    )

    assert result.failure?
  end

  test "prepare and pick happy path" do
    @hero[:components][:progression][:experience] = Sim::Upgrades::Draft::LEVEL_UNIT
    prepared = Sim::Campaign::HeroDraft.prepare(
      campaign: @campaign,
      catalog: catalog,
      player_id: "player-1",
      hero_id: @hero[:id],
      rng: Sim::Rng::Seeded.new(1)
    )
    assert prepared.ok?
    upgrade_id = prepared.value.find_entity("player-1", @hero[:id]).dig(:components, :progression, :pending_draft).first

    picked = Sim::Campaign::HeroDraft.pick(
      campaign: prepared.value,
      player_id: "player-1",
      hero_id: @hero[:id],
      upgrade_id: upgrade_id
    )

    assert picked.ok?
    hero = picked.value.find_entity("player-1", @hero[:id])
    assert_includes hero.dig(:components, :progression, :picked_upgrade_ids), upgrade_id
    assert_empty hero.dig(:components, :progression, :pending_draft)
  end

  test "loss grants half a level and win grants a full level to general" do
    assert @hero.dig(:components, :hero, :general)

    loser = { id: "loser", roster: [ @hero.deep_dup ] }
    winner_hero = @hero.deep_dup
    winner_hero[:id] = "winner-hero"
    winner = { id: "winner", roster: [ winner_hero ] }

    Sim::Upgrades::Draft.grant_battle_credit!(loser, Sim::Upgrades::Draft::LOSS_CREDIT)
    Sim::Upgrades::Draft.grant_battle_credit!(winner, Sim::Upgrades::Draft::WIN_CREDIT)

    assert_equal 1, loser[:roster].first.dig(:components, :progression, :experience)
    refute Sim::Upgrades::Draft.level_ready?(loser[:roster].first)

    Sim::Upgrades::Draft.grant_battle_credit!(loser, Sim::Upgrades::Draft::LOSS_CREDIT)
    assert Sim::Upgrades::Draft.level_ready?(loser[:roster].first)

    assert_equal 2, winner[:roster].first.dig(:components, :progression, :experience)
    assert Sim::Upgrades::Draft.level_ready?(winner[:roster].first)
  end

  test "non-general cannot level even with credit" do
    @hero[:components][:hero][:general] = false
    @hero[:components][:progression][:experience] = 10
    refute Sim::Upgrades::Draft.level_ready?(@hero)
  end

  test "pick rejects upgrade outside draft" do
    @hero[:components][:progression][:pending_draft] = [ "rune_blade" ]
    result = Sim::Campaign::HeroDraft.pick(
      campaign: @campaign,
      player_id: "player-1",
      hero_id: @hero[:id],
      upgrade_id: "meteor_hammer"
    )

    assert result.failure?
  end
end
