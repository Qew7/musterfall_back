require "test_helper"

class SimUpgradesDraftTest < ActiveSupport::TestCase
  setup do
    @game = create_active_game
    assign_first_faction!(@game)
    @campaign = Sim::Persistence::CampaignRepository.new.load(@game.reload)
    @player = @campaign.find_player("player-1")
    @hero = @player[:roster].find { |entry| entry.dig(:components, :hero, :general) }
    @rng = Sim::Rng::Seeded.new(42)
  end

  test "roll returns three unique upgrades with one common and one faction" do
    picks = Sim::Upgrades::Draft.roll(@hero, catalog, @rng)

    assert_equal 3, picks.length
    assert_equal picks.length, picks.uniq.length

    meta = picks.index_by { |id| id }.transform_values { |id| catalog.hero_upgrades.find { |entry| entry[:id] == id } }
    assert meta.values.any? { |entry| entry[:faction_id].nil? }, "expected a common upgrade"
    assert meta.values.any? { |entry| entry[:faction_id] == @hero.dig(:components, :identity, :faction_id) }, "expected a faction upgrade"
  end

  test "non-repeatable upgrades are blocked after pick" do
    upgrade_id = "rune_blade"
    @hero[:components][:progression][:experience] = 10
    assert Sim::Upgrades::Draft.apply!(@hero, upgrade_id, catalog: catalog)

    picks = Sim::Upgrades::Draft.roll(@hero, catalog, @rng)
    assert_not_includes picks, upgrade_id
  end

  test "repeatable upgrades stay eligible after pick" do
    upgrade_id = "veteran_drill"
    @hero[:components][:progression][:experience] = 10
    assert Sim::Upgrades::Draft.apply!(@hero, upgrade_id, catalog: catalog)

    eligible = Sim::Upgrades::Draft.eligible_pool(catalog.hero_upgrades, faction_id: nil, blocked: @hero.dig(:components, :progression, :picked_upgrade_ids), hero: @hero)
    assert eligible.any? { |entry| entry[:id] == upgrade_id }
  end

  test "mount upgrade replaces previous mount bonuses" do
    skip unless @hero.dig(:components, :identity, :faction_id) == "empire"

    @hero[:components][:progression][:experience] = 20
    assert Sim::Upgrades::Draft.apply!(@hero, "warhorse", catalog: catalog)
    assert_equal "warhorse", @hero.dig(:components, :hero, :mount_id)

    @hero[:components][:progression][:level] = 2
    assert Sim::Upgrades::Draft.apply!(@hero, "winged_mount", catalog: catalog)

    assert_equal "winged_mount", @hero.dig(:components, :hero, :mount_id)
    assert_equal "monster", @hero.dig(:components, :formation, :model_class)
    assert_equal 20, @hero.dig(:components, :combat, :movement)
    refute_includes @hero.dig(:components, :abilities), "fast"
    assert_includes @hero.dig(:components, :abilities), "flying"
  end

  test "picked mount upgrade cannot be chosen again" do
    skip unless @hero.dig(:components, :identity, :faction_id) == "empire"

    @hero[:components][:progression][:experience] = 10
    assert Sim::Upgrades::Draft.apply!(@hero, "warhorse", catalog: catalog)

    blocked = @hero.dig(:components, :progression, :picked_upgrade_ids).to_a
    refute Sim::Upgrades::Draft.upgrade_eligible?({ id: "warhorse", min_level: 1, general_only: false }, @hero, blocked: blocked)
  end

  test "elite upgrades require level three" do
    elite = catalog.hero_upgrades.find { |entry| entry[:min_level] == 3 && entry[:faction_id] == @hero.dig(:components, :identity, :faction_id) }
    skip "no elite upgrade for faction" unless elite

    blocked = @hero.dig(:components, :progression, :picked_upgrade_ids).to_a
    refute Sim::Upgrades::Draft.upgrade_eligible?(elite, @hero, blocked: blocked)

    @hero[:components][:progression][:level] = 2
    assert Sim::Upgrades::Draft.upgrade_eligible?(elite, @hero, blocked: blocked)
  end

  test "general-only upgrades reject non-generals" do
    elite = catalog.hero_upgrades.find { |entry| entry[:general_only] }
    skip "no general-only upgrade" unless elite

    @hero[:components][:progression][:level] = 2
    @hero[:components][:hero][:general] = false
    blocked = @hero.dig(:components, :progression, :picked_upgrade_ids).to_a
    refute Sim::Upgrades::Draft.upgrade_eligible?(elite, @hero, blocked: blocked)
  end

  test "winged mount switches hero to monster footprint at level three" do
    skip unless @hero.dig(:components, :identity, :faction_id) == "empire"

    @hero[:components][:progression][:level] = 2
    @hero[:components][:progression][:experience] = 10
    assert Sim::Upgrades::Draft.apply!(@hero, "winged_mount", catalog: catalog)

    assert_equal "monster", @hero.dig(:components, :formation, :model_class)
    assert_equal 2, @hero.dig(:components, :formation, :model_width)
    assert_equal 20, @hero.dig(:components, :combat, :movement)
  end

  test "demon form transforms chaos general at level three" do
    skip unless @hero.dig(:components, :identity, :faction_id) == "chaos"

    @hero[:components][:progression][:level] = 2
    @hero[:components][:progression][:experience] = 10
    assert Sim::Upgrades::Draft.apply!(@hero, "demon_form", catalog: catalog)

    assert @hero.dig(:components, :hero, :transformed)
    assert_equal "monster", @hero.dig(:components, :formation, :model_class)
    assert_includes @hero.dig(:components, :abilities), "flying"
  end
end
