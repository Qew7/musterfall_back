require "test_helper"

class BalanceArmyStageTest < ActiveSupport::TestCase
  test "mixed schedules every stage and budget without consuming random numbers" do
    configs = 9.times.map { |i| Balance::Synthetic::ArmyStage.resolve({ army_stage: "mixed" }, battle_no: i) }
    assert_equal %w[early mid late early mid late early mid late], configs.map { |c| c[:army_stage] }
    Balance::Synthetic::ArmyStage::PRESETS.each do |stage, preset|
      assert_equal preset[:budgets], configs.select { |c| c[:army_stage] == stage }.map { |c| c[:target_points] }
    end
  end

  test "new runs default to mixed while stored legacy configuration is preserved" do
    assert_equal "mixed", Balance::Simulation.normalize_config({})[:army_stage]
    config = { budget_mode: "fixed", target_points: 321 }
    assert_equal config, Balance::Synthetic::ArmyStage.resolve(config, battle_no: 8)
    assert_raises(ArgumentError) { Balance::Simulation.normalize_config(army_stage: "typo") }
  end

  test "all factions respect stages and spend only on troops within the roster cap" do
    catalog = Sim::Catalog::Loader.load
    Balance::Synthetic::ArmyStage::PRESETS.each do |stage, preset|
      catalog.selectable_factions.each do |faction|
        army = Balance::Synthetic::Army.build!(
          catalog: catalog, faction_id: faction[:id], budget: preset[:budgets].last,
          hero_level: preset[:hero_level], rng: Sim::Rng::Seeded.new(89), player_id: "test",
          recruit_strategy: "push_elite", battle_only: true, recruit_access: preset[:access], recruit_tiers: preset[:tiers]
        )
        assert_equal preset[:access], army[:recruitment][:access], stage
        leaked = preset[:budgets].last - army[:recruitment][:spent] - army[:recruitment][:unspent]
        assert_operator leaked, :>=, 0
        assert_equal 0, leaked % Sim::Campaign::RecruitAccess::REFRESH_COST
        assert_operator army[:roster].size, :<=, 12
        assert_operator army[:recruitment][:unspent], :>=, 0
        army[:roster].select { |e| e[:kind] == "unit" }.each do |entity|
          assert_includes preset[:tiers], catalog.template(entity[:template_id])[:recruit_tier]
        end
        if stage == "early"
          assert_equal 1, army[:roster].count { |e| e[:kind] == "hero" }
        end
      end
    end
  end
end
