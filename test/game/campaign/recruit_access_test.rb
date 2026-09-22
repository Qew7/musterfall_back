require "test_helper"

class SimCampaignRecruitAccessTest < ActiveSupport::TestCase
  test "slot ladder caps heroes at 3 and rare at 4" do
    assert_equal({ hero: 0, elite: 0, rare: 0 }, Sim::Campaign::RecruitAccess.slots_for(0))
    assert_equal({ hero: 1, elite: 1, rare: 0 }, Sim::Campaign::RecruitAccess.slots_for(1))
    assert_equal({ hero: 2, elite: 2, rare: 1 }, Sim::Campaign::RecruitAccess.slots_for(2))
    assert_equal({ hero: 3, elite: 3, rare: 2 }, Sim::Campaign::RecruitAccess.slots_for(3))
    assert_equal({ hero: 3, elite: 5, rare: 4 }, Sim::Campaign::RecruitAccess.slots_for(5))
  end

  test "restore cost scales with lost models" do
    template = { cost: 100, models: 10 }
    assert_equal 30, Sim::Campaign::RecruitAccess.model_restore_cost(template, 3)
  end

  test "affordable restore models caps by treasury" do
    template = { cost: 100, models: 10 }
    assert_equal 2, Sim::Campaign::RecruitAccess.affordable_restore_models(template, 25, 5)
    assert_equal 0, Sim::Campaign::RecruitAccess.affordable_restore_models(template, 5, 5)
    assert_equal 5, Sim::Campaign::RecruitAccess.affordable_restore_models(template, 100, 5)
  end

  test "shop offer grows from 3 to 6 with access" do
    assert_equal 3, Sim::Campaign::RecruitAccess.offer_size(0)
    assert_equal 4, Sim::Campaign::RecruitAccess.offer_size(1)
    assert_equal 5, Sim::Campaign::RecruitAccess.offer_size(2)
    assert_equal 6, Sim::Campaign::RecruitAccess.offer_size(3)
    assert_equal 6, Sim::Campaign::RecruitAccess.offer_size(5)
  end

  test "locked tiers stay off the shop" do
    assert_equal %w[line], Sim::Campaign::RecruitAccess.unlocked_tiers(0)
    assert_equal %w[line elite], Sim::Campaign::RecruitAccess.unlocked_tiers(1)
    assert_equal %w[line elite rare], Sim::Campaign::RecruitAccess.unlocked_tiers(2)
  end

  test "held shop skips one automatic roll" do
    player = {
      faction_id: "empire", recruit_access: 0, treasury: 200,
      market_offer: %w[frozen_offer], hold_market: true
    }
    rng = Sim::Rng::Seeded.new(1)
    Sim::Campaign::RecruitAccess.roll_offer!(player, catalog, rng)
    assert_equal %w[frozen_offer], player[:market_offer]
    assert_equal false, player[:hold_market]

    Sim::Campaign::RecruitAccess.roll_offer!(player, catalog, rng)
    refute_includes player[:market_offer], "frozen_offer"
  end

  test "paid refresh clears a held shop" do
    player = {
      faction_id: "empire", recruit_access: 0, treasury: 200,
      market_offer: %w[frozen_offer], hold_market: true
    }
    assert Sim::Campaign::RecruitAccess.refresh_offer!(player, catalog, Sim::Rng::Seeded.new(2))
    assert_equal false, player[:hold_market]
    refute_includes player[:market_offer], "frozen_offer"
    assert_equal 150, player[:treasury]
  end
end
