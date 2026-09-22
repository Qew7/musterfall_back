require "test_helper"

class SimCampaignNeutralRecruitmentTest < ActiveSupport::TestCase
  setup do
    base = catalog.template("state_swords")
    @mercenaries = %w[line elite rare].map do |tier|
      base.merge(id: "contract_#{tier}", faction_id: "mercenaries", recruit_tier: tier, cost: 50, abilities: [])
    end
    @neutral = { id: "mercenaries", neutral: true, unit_pool: @mercenaries.map { |entry| entry[:id] }, hero_pool: [] }
    @neutral_catalog = make_catalog(factions: catalog.selectable_factions + [ @neutral ], units: catalog.units + @mercenaries)
  end

  test "neutral templates retain ownership and are offered to each playable faction" do
    @neutral_catalog.selectable_factions.each do |faction|
      own = @neutral_catalog.unit_templates(faction[:id])
      offered = @neutral_catalog.recruitable_unit_templates(faction[:id])
      assert_empty own & @mercenaries
      assert_empty @mercenaries - offered
      assert own.all? { |template| template[:faction_id] == faction[:id] }
    end
    assert_empty @neutral_catalog.recruitable_unit_templates(nil)
    assert_empty @neutral_catalog.recruitable_unit_templates("mercenaries")
    assert_empty @neutral_catalog.recruitable_unit_templates("missing")
  end

  test "neither humans nor bots can select a neutral faction" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    campaign.players.each do |player|
      result = Sim::Campaign::AssignFaction.call(
        campaign: campaign, catalog: @neutral_catalog, player_id: player[:id], faction_id: "mercenaries"
      )
      assert_equal "neutral faction cannot be selected", result.error
      assert_nil campaign.find_player(player[:id])[:faction_id]
    end
  end

  test "every playable faction can hire neutral units without changing their identity" do
    @neutral_catalog.selectable_factions.each do |faction|
      campaign = campaign_for(faction[:id])
      result = recruit(campaign, "contract_line")
      assert result.ok?, "#{faction[:id]}: #{result.error}"
      player = result.value.find_player("player-1")
      assert_equal 450, player[:treasury]
      assert_equal faction[:id], player[:faction_id]
      assert_equal "mercenaries", player[:roster].last.dig(:components, :identity, :faction_id)
      assert_equal 500, campaign.find_player("player-1")[:treasury]
    end
  end

  test "hiring still requires a chosen playable faction and rejects foreign faction units" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    assert_equal "faction required", recruit(campaign, "contract_line").error

    campaign = campaign_for("empire")
    assert_equal "template faction mismatch", recruit(campaign, "orc_brutes").error
    campaign.find_player("player-1")[:faction_id] = "mercenaries"
    assert_equal "template faction mismatch", recruit(campaign, "contract_line").error
  end

  test "neutral elites and rares use the same limited slots as faction units" do
    { "elite" => 1, "rare" => 2 }.each do |tier, access|
      campaign = campaign_for("empire")
      campaign.find_player("player-1")[:recruit_access] = access - 1
      assert_equal "recruit slot unavailable", recruit(campaign, "contract_#{tier}").error

      campaign.find_player("player-1")[:recruit_access] = access
      result = recruit(campaign, "contract_#{tier}")
      assert result.ok?, result.error
      campaign = result.value
      assert_equal "recruit slot unavailable", recruit(campaign, "contract_#{tier}").error
      own_template = @neutral_catalog.unit_templates("empire").find { |entry| entry[:recruit_tier] == tier }
      campaign.find_player("player-1")[:treasury] = 10_000
      assert_equal "recruit slot unavailable", recruit(campaign, own_template[:id]).error
    end
  end

  test "automatic selection excludes neutral even when the playable pool has no own units" do
    sparse_catalog = mercenary_only_catalog
    result = Sim::Campaign::PrepareRound.call(
      campaign: Sim::Campaign::Create.call(player_count: 2).value,
      catalog: sparse_catalog, rng: Sim::Rng::Seeded.new(5)
    )
    assert result.ok?, result.error
    assert_equal [ "test_realm", "test_realm" ], result.value.players.map { |player| player[:faction_id] }
    bot = result.value.find_player("player-2")
    assert bot[:roster].any?, "bot must be able to buy the shared neutral pool"
    assert bot[:roster].all? { |entity| entity.dig(:components, :identity, :faction_id) == "mercenaries" }
  end

  test "balance armies hire neutral units but never select their faction" do
    sparse_catalog = mercenary_only_catalog
    rng = Sim::Rng::Seeded.new(7)
    assert_equal [ "test_realm", "test_realm" ], Balance::Synthetic::Play.pick_factions(sparse_catalog, {}, rng)
    assert_raises(ArgumentError) do
      Balance::Synthetic::Play.pick_factions(sparse_catalog, { faction_left: "mercenaries" }, rng)
    end
    army = Balance::Synthetic::Army.build!(
      catalog: sparse_catalog, faction_id: "test_realm", budget: 100, hero_level: 1,
      rng: rng, player_id: "test-army", recruit_access: 0, recruit_tiers: [ "line" ], battle_only: true
    )
    assert_equal "test_realm", army[:faction_id]
    assert army[:roster].any?
    assert_equal [ "contract_line" ], army[:roster].map { |entity| entity[:template_id] }.uniq
  end

  private

  def make_catalog(factions:, units:)
    Sim::Catalog.new(
      formation_rules: catalog.formation_rules, model_classes: [], factions: factions,
      units: units, heroes: catalog.heroes, abilities: catalog.abilities, hero_upgrades: catalog.hero_upgrades
    )
  end

  def mercenary_only_catalog
    make_catalog(
      factions: [ @neutral, { id: "test_realm", neutral: false, unit_pool: [], hero_pool: [] } ],
      units: @mercenaries
    )
  end

  def campaign_for(faction_id)
    result = Sim::Campaign::AssignFaction.call(
      campaign: Sim::Campaign::Create.call(player_count: 2).value, catalog: @neutral_catalog,
      player_id: "player-1", faction_id: faction_id, school_key: starter_school_key(faction_id)
    )
    assert result.ok?, result.error
    result.value.find_player("player-1")[:treasury] = 500
    result.value
  end

  def recruit(campaign, template_id)
    on_market!(campaign.find_player("player-1"), template_id)
    Sim::Campaign::Recruit.call(campaign: campaign, catalog: @neutral_catalog, player_id: "player-1", template_id: template_id)
  end
end
