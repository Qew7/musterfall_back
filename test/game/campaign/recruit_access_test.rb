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
end
