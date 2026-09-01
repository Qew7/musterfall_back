require "test_helper"

class SimCampaignRecruitTest < ActiveSupport::TestCase
  setup do
    @game = create_active_game
    assign_first_faction!(@game)
    @campaign = Sim::Persistence::CampaignRepository.new.load(@game.reload)
    player = @campaign.find_player("player-1")
    @template = catalog.unit_templates(player[:faction_id])
      .select { |template| template[:recruit_tier] == "line" && template[:cost] <= player[:treasury] }
      .min_by { |template| template[:cost] }
  end

  test "recruit spends treasury and adds entity" do
    result = Sim::Campaign::Recruit.call(
      campaign: @campaign,
      catalog: catalog,
      player_id: "player-1",
      template_id: @template[:id]
    )

    assert result.ok?, result.error
    player = result.value.find_player("player-1")
    assert_equal Sim::Constants::STARTING_TREASURY - @template[:cost], player[:treasury]
    assert player[:roster].any? { |entity| entity[:template_id] == @template[:id] }
  end

  test "recruit fails without treasury" do
    @campaign.find_player("player-1")[:treasury] = 0
    result = Sim::Campaign::Recruit.call(
      campaign: @campaign,
      catalog: catalog,
      player_id: "player-1",
      template_id: @template[:id]
    )

    assert result.failure?
    assert_equal "insufficient treasury", result.error
  end

  test "recruit fails for unknown template" do
    result = Sim::Campaign::Recruit.call(
      campaign: @campaign,
      catalog: catalog,
      player_id: "player-1",
      template_id: "missing"
    )

    assert result.failure?
  end

  test "wizard requires an available school and receives two seeded unique spells" do
    player = @campaign.find_player("player-1")
    player[:recruit_access] = 1
    player[:treasury] = 1000
    wizard = catalog.hero_templates(player[:faction_id]).find { |hero| hero[:abilities].include?("wizard") }

    with_spell_api(
      schools: %i[pyromancy celestial],
      spell_keys: %i[fireball inferno cinder_shield]
    ) do
      result = Sim::Campaign::Recruit.call(
        campaign: @campaign,
        catalog: catalog,
        player_id: "player-1",
        template_id: wizard[:id],
        school_key: "pyromancy",
        rng: Sim::Rng::Seeded.new(17)
      )

      assert result.ok?, result.error
      hero = result.value.find_player("player-1")[:roster].last
      assert_equal "pyromancy", hero.dig(:components, :hero, :magic_school)
      assert_equal 2, hero.dig(:components, :hero, :spell_keys).uniq.length
      assert_empty hero.dig(:components, :hero, :spell_keys) - %w[fireball inferno cinder_shield]
    end
  end

  test "non-wizard rejects a magic school" do
    result = Sim::Campaign::Recruit.call(
      campaign: @campaign,
      catalog: catalog,
      player_id: "player-1",
      template_id: @template[:id],
      school_key: "pyromancy"
    )

    assert result.failure?
    assert_equal "magic school is only valid for wizards", result.error
  end

  test "elite unit blocked until access upgraded" do
    elite = catalog.unit_templates(@campaign.find_player("player-1")[:faction_id])
      .find { |template| template[:recruit_tier] == "elite" }
    skip "no elite unit" unless elite

    @campaign.find_player("player-1")[:treasury] = elite[:cost]
    result = Sim::Campaign::Recruit.call(
      campaign: @campaign,
      catalog: catalog,
      player_id: "player-1",
      template_id: elite[:id]
    )

    assert result.failure?
    assert_equal "recruit slot unavailable", result.error
  end

  test "chaos spawn spends all treasury and keeps bounded seeded mutations" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    campaign = Sim::Campaign::AssignFaction.call(
      campaign: campaign,
      catalog: catalog,
      player_id: "player-1",
      faction_id: "chaos",
      rng: Sim::Rng::Seeded.new(2)
    ).value
    player = campaign.find_player("player-1")
    player[:recruit_access] = 0
    blocked = Sim::Campaign::Recruit.call(
      campaign: campaign,
      catalog: catalog,
      player_id: player[:id],
      template_id: "rift_mutant",
      rng: Sim::Rng::Seeded.new(9)
    )
    assert blocked.failure?

    player[:recruit_access] = 2
    player[:treasury] = 1000

    result = Sim::Campaign::Recruit.call(
      campaign: campaign,
      catalog: catalog,
      player_id: player[:id],
      template_id: "rift_mutant",
      rng: Sim::Rng::Seeded.new(9)
    )

    assert result.ok?, result.error
    recruited = result.value.find_player(player[:id])
    spawn = recruited[:roster].find { |entity| entity[:template_id] == "rift_mutant" }
    assert_equal 0, recruited[:treasury]
    assert_equal 1000, spawn.dig(:components, :economy, :cost)
    assert_operator spawn.dig(:components, :health, :max), :<=, 12
    assert_operator spawn.dig(:components, :combat, :melee), :<=, 8
    assert_operator spawn.dig(:components, :combat, :skill), :<=, 6
    assert_operator spawn.dig(:components, :combat, :attacks), :<=, 4
    assert_operator spawn.dig(:components, :combat, :movement), :<=, 8
    extras = spawn.dig(:components, :abilities) - %w[monster fear]
    assert_operator extras.length, :<=, 2

    replay = Sim::Campaign::Create.call(player_count: 2).value
    replay = Sim::Campaign::AssignFaction.call(
      campaign: replay,
      catalog: catalog,
      player_id: "player-1",
      faction_id: "chaos",
      rng: Sim::Rng::Seeded.new(2)
    ).value
    replay.find_player("player-1")[:recruit_access] = 2
    replay.find_player("player-1")[:treasury] = 1000
    again = Sim::Campaign::Recruit.call(
      campaign: replay,
      catalog: catalog,
      player_id: "player-1",
      template_id: "rift_mutant",
      rng: Sim::Rng::Seeded.new(9)
    ).value.find_player("player-1")[:roster].find { |entity| entity[:template_id] == "rift_mutant" }
    assert_equal spawn.dig(:components, :abilities), again.dig(:components, :abilities)
    assert_equal spawn.dig(:components, :combat), again.dig(:components, :combat)
    assert_equal spawn.dig(:components, :health, :max), again.dig(:components, :health, :max)
  end
end
