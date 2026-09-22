require "test_helper"

class SimCampaignMarketOfferTest < ActiveSupport::TestCase
  setup do
    @campaign = Sim::Campaign::AssignFaction.call(
      campaign: Sim::Campaign::Create.call(player_count: 2).value,
      catalog: catalog,
      player_id: "player-1",
      faction_id: "empire",
      rng: Sim::Rng::Seeded.new(1)
    ).value
    @player = @campaign.find_player("player-1")
  end

  test "rolled shop is n units, half own, includes a line, and hides locked tiers" do
    ids = Sim::Campaign::RecruitAccess.sample_offer(@player, catalog, Sim::Rng::Seeded.new(11))
    templates = ids.map { |id| catalog.template(id) }

    assert_equal 3, ids.size
    assert_equal ids.uniq, ids
    assert templates.any? { |template| template[:recruit_tier] == "line" }
    assert_operator templates.count { |template| template[:faction_id] == "empire" }, :>=, 1
    assert templates.all? { |template| template[:recruit_tier] == "line" }
    assert templates.none? { |template| template[:kind] == "hero" }
  end

  test "higher tiers appear less often than line" do
    @player[:recruit_access] = 2
    counts = Hash.new(0)
    80.times do |seed|
      Sim::Campaign::RecruitAccess.sample_offer(@player, catalog, Sim::Rng::Seeded.new(seed + 1)).each do |id|
        counts[catalog.template(id)[:recruit_tier]] += 1
      end
    end

    assert_operator counts["line"], :>, counts["elite"]
    assert_operator counts["elite"], :>, counts["rare"]
  end

  test "prepare_round rolls a shop and recruit outside it is rejected" do
    prepared = Sim::Campaign::PrepareRound.call(
      campaign: @campaign, catalog: catalog, rng: Sim::Rng::Seeded.new(4)
    )
    assert prepared.ok?, prepared.error
    player = prepared.value.find_player("player-1")
    assert_equal 3, player[:market_offer].size

    outsider = catalog.recruitable_unit_templates("empire")
      .find { |template| template[:recruit_tier] == "line" && player[:market_offer].exclude?(template[:id]) }
    skip "offer covered the whole line pool" unless outsider

    result = Sim::Campaign::Recruit.call(
      campaign: prepared.value, catalog: catalog, player_id: "player-1", template_id: outsider[:id]
    )
    assert_equal "not on market", result.error
  end

  test "upgrade_access keeps the current shop" do
    Sim::Campaign::RecruitAccess.roll_offer!(@player, catalog, Sim::Rng::Seeded.new(2))
    offer = @player[:market_offer].dup
    @player[:treasury] = 10_000

    result = Sim::Campaign::UpgradeAccess.call(campaign: @campaign, player_id: "player-1")
    assert result.ok?, result.error
    assert_equal offer, result.value.find_player("player-1")[:market_offer]
  end

  test "hiring unpaid_company makes the next refresh free once" do
    @player[:market_offer] = [ "unpaid_company" ]
    @player[:treasury] = 200

    hired = Sim::Campaign::Recruit.call(
      campaign: @campaign, catalog: catalog, player_id: "player-1", template_id: "unpaid_company"
    )
    assert hired.ok?, hired.error
    player = hired.value.find_player("player-1")
    assert_equal 100, player[:treasury]
    assert_equal true, player[:free_market_refresh]

    free = Sim::Campaign::RefreshMarket.call(
      campaign: hired.value, catalog: catalog, player_id: "player-1", rng: Sim::Rng::Seeded.new(5)
    )
    assert free.ok?, free.error
    player = free.value.find_player("player-1")
    assert_equal 100, player[:treasury]
    assert_equal false, player[:free_market_refresh]

    paid = Sim::Campaign::RefreshMarket.call(
      campaign: free.value, catalog: catalog, player_id: "player-1", rng: Sim::Rng::Seeded.new(6)
    )
    assert paid.ok?, paid.error
    assert_equal 50, paid.value.find_player("player-1")[:treasury]
  end

  test "refresh_market spends 50 and replaces the offer" do
    Sim::Campaign::RecruitAccess.roll_offer!(@player, catalog, Sim::Rng::Seeded.new(2))
    @player[:treasury] = 80

    result = Sim::Campaign::RefreshMarket.call(
      campaign: @campaign, catalog: catalog, player_id: "player-1", rng: Sim::Rng::Seeded.new(9)
    )
    assert result.ok?, result.error
    player = result.value.find_player("player-1")
    assert_equal 30, player[:treasury]
    assert_equal 3, player[:market_offer].size
    player[:market_offer].each { |id| assert catalog.template(id) }
  end

  test "buying a unit leaves the shop card but it can roll again" do
    Sim::Campaign::RecruitAccess.roll_offer!(@player, catalog, Sim::Rng::Seeded.new(2))
    bought = @player[:market_offer].first
    @player[:treasury] = 10_000

    result = Sim::Campaign::Recruit.call(
      campaign: @campaign, catalog: catalog, player_id: "player-1", template_id: bought
    )
    assert result.ok?, result.error
    player = result.value.find_player("player-1")
    assert_not_includes player[:market_offer], bought
    assert_includes Sim::Campaign::RecruitAccess.unlocked_unit_pool(player, catalog).map { |template| template[:id] }, bought

    rerolls = 20.times.map { |seed|
      Sim::Campaign::RecruitAccess.sample_offer(player, catalog, Sim::Rng::Seeded.new(seed + 40))
    }
    assert rerolls.any? { |ids| ids.include?(bought) }, "#{bought} stayed out of later rolls"
  end

  test "slot-full rares stay in the unlocked pool" do
    @player[:recruit_access] = 2
    @player[:roster] << {
      kind: "unit",
      template_id: "great_cannon",
      components: { economy: { cost: 225 } }
    }
    refute Sim::Campaign::RecruitAccess.allowed?(@player, catalog, catalog.template("great_cannon"))
    assert_includes Sim::Campaign::RecruitAccess.unlocked_unit_pool(@player, catalog).map { |template| template[:id] }, "great_cannon"
  end
end
