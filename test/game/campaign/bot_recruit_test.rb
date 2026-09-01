require "test_helper"

class SimCampaignBotRecruitTest < ActiveSupport::TestCase
  test "assigns a strategy and shops within treasury" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    bot = campaign.find_player("player-2")
    faction = catalog.factions.first
    assigned = Sim::Campaign::AssignFaction.call(
      campaign: campaign,
      catalog: catalog,
      player_id: bot[:id],
      faction_id: faction[:id],
      rng: Sim::Rng::Seeded.new(1)
    )
    assert assigned.ok?

    result = Sim::Campaign::BotRecruit.call(
      campaign: assigned.value,
      catalog: catalog,
      player_id: bot[:id],
      rng: Sim::Rng::Seeded.new(3)
    )

    assert result.ok?
    player = result.value.find_player(bot[:id])
    assert_includes Sim::Campaign::BotRecruit::STRATEGIES.keys, player[:recruit_strategy]
    assert player[:treasury] >= 0
    assert player[:roster].size >= 1
  end

  test "push_elite upgrades when treasury allows" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    bot = campaign.find_player("player-2")
    faction = catalog.factions.first
    campaign = Sim::Campaign::AssignFaction.call(
      campaign: campaign,
      catalog: catalog,
      player_id: bot[:id],
      faction_id: faction[:id],
      rng: Sim::Rng::Seeded.new(1)
    ).value
    bot = campaign.find_player(bot[:id])
    bot[:recruit_strategy] = "push_elite"
    bot[:treasury] = 800

    result = Sim::Campaign::BotRecruit.call(
      campaign: campaign,
      catalog: catalog,
      player_id: bot[:id],
      rng: Sim::Rng::Seeded.new(11)
    )

    assert result.ok?
    player = result.value.find_player(bot[:id])
    assert_operator player[:recruit_access], :>=, 1
  end

  test "restores damaged units before shopping within strategy reserve" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    bot = campaign.find_player("player-2")
    faction = catalog.factions.first
    campaign = Sim::Campaign::AssignFaction.call(
      campaign: campaign,
      catalog: catalog,
      player_id: bot[:id],
      faction_id: faction[:id],
      rng: Sim::Rng::Seeded.new(1)
    ).value
    bot = campaign.find_player(bot[:id])
    bot[:recruit_strategy] = "balanced"
    bot[:recruit_access] = 0

    template = catalog.unit_templates(bot[:faction_id])
      .select { |entry| entry[:recruit_tier] == "line" && entry[:models] > 4 }
      .min_by { |entry| entry[:cost] }
    recruit = Sim::Campaign::Recruit.call(
      campaign: campaign,
      catalog: catalog,
      player_id: bot[:id],
      template_id: template[:id]
    )
    assert recruit.ok?, recruit.error
    campaign = recruit.value
    bot = campaign.find_player(bot[:id])
    entity = bot[:roster].find { |entry| entry[:template_id] == template[:id] }
    model_health = entity.dig(:components, :health, :model_health)
    max_models = entity.dig(:components, :formation, :models)
    entity[:state][:current_health] = model_health * (max_models - 4)
    per = (template[:cost].to_f / template[:models]).ceil
    bot[:treasury] = Sim::Campaign::BotRecruit::STRATEGIES["balanced"][:upgrade_reserve] + (per * 3)

    before_health = entity.dig(:state, :current_health)
    result = Sim::Campaign::BotRecruit.call(
      campaign: campaign,
      catalog: catalog,
      player_id: bot[:id],
      rng: Sim::Rng::Seeded.new(2)
    )

    assert result.ok?
    player = result.value.find_player(bot[:id])
    restored = player[:roster].find { |entry| entry[:id] == entity[:id] }
    assert_operator restored.dig(:state, :current_health), :>, before_health
    assert_operator player[:treasury], :>=, 0
  end

  test "chaos spawn remains recruitable when catalog cost exceeds leftover treasury" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    bot = campaign.find_player("player-2")
    campaign = Sim::Campaign::AssignFaction.call(
      campaign: campaign,
      catalog: catalog,
      player_id: bot[:id],
      faction_id: "chaos",
      rng: Sim::Rng::Seeded.new(1)
    ).value
    bot = campaign.find_player(bot[:id])
    bot[:recruit_access] = 2
    bot[:treasury] = 80
    spawn = catalog.template("rift_mutant")
    shop = Sim::Campaign::BotRecruit.new(campaign, catalog, bot[:id], Sim::Rng::Seeded.new(1))

    assert_operator spawn[:cost], :>, 80
    assert_includes shop.send(:recruitable, bot).map { |template| template[:id] }, "rift_mutant"
  end
end
