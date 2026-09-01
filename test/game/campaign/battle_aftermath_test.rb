require "test_helper"

class SimCampaignBattleAftermathTest < ActiveSupport::TestCase
  test "non-permanent losses auto-restore and max models stays at template size" do
    player = unit_player(models: 10, current_health: 10)
    campaign = campaign_for(player)

    never_permanent = Object.new
    never_permanent.define_singleton_method(:rand) { |_max| 1 }

    battle = unit_battle(starting_models: 10, models_remaining: 5, current_health: 5)
    Sim::Campaign::BattleAftermath.apply!(campaign: campaign, battles: [ battle ], rng: never_permanent)

    entity = player[:roster].first
    assert_equal 10, entity.dig(:components, :formation, :models)
    assert_equal 10, entity.dig(:state, :current_health)
  end

  test "permanent losses stay missing but do not reduce roster max" do
    player = unit_player(models: 10, current_health: 10)
    campaign = campaign_for(player)

    always_permanent = Object.new
    always_permanent.define_singleton_method(:rand) { |_max| 0 }

    battle = unit_battle(starting_models: 10, models_remaining: 5, current_health: 5)
    Sim::Campaign::BattleAftermath.apply!(campaign: campaign, battles: [ battle ], rng: always_permanent)

    entity = player[:roster].first
    assert_equal 10, entity.dig(:components, :formation, :models)
    assert_equal 5, entity.dig(:state, :current_health)
  end

  test "mixed permanent rolls leave survivors plus auto-restored models" do
    player = unit_player(models: 10, current_health: 10)
    campaign = campaign_for(player)

    rolls = [ 0, 1, 1, 0, 1 ]
    rng = Object.new
    rng.define_singleton_method(:rand) { |_max| rolls.shift || 1 }

    battle = unit_battle(starting_models: 10, models_remaining: 5, current_health: 5)
    Sim::Campaign::BattleAftermath.apply!(campaign: campaign, battles: [ battle ], rng: rng)

    entity = player[:roster].first
    assert_equal 10, entity.dig(:components, :formation, :models)
    assert_equal 8, entity.dig(:state, :current_health)
  end

  test "unit is removed only when every casualty roll is permanent" do
    player = unit_player(models: 10, current_health: 10)
    campaign = campaign_for(player)

    always_permanent = Object.new
    always_permanent.define_singleton_method(:rand) { |_max| 0 }

    battle = unit_battle(starting_models: 10, models_remaining: 0, current_health: 0)
    Sim::Campaign::BattleAftermath.apply!(campaign: campaign, battles: [ battle ], rng: always_permanent)

    assert_empty player[:roster]
  end

  test "general hero skips death and revives fully" do
    player = {
      id: "player-1",
      roster: [
        {
          id: "hero-1",
          kind: "hero",
          components: {
            formation: { models: 1, frontage: 1, max_files: 5, model_width: 1, model_depth: 1 },
            health: { model_health: 3, max: 3, permanent_losses: 0 },
            hero: { mounted: false, general: true }
          },
          state: { current_health: 0, is_routing: true }
        }
      ]
    }
    campaign = campaign_for(player)
    rng = Object.new
    rng.define_singleton_method(:rand) { |_max| 0 }

    battle = {
      left: {
        player_id: "player-1",
        combatants: [
          { entity_id: "hero-1", starting_models: 1, models_remaining: 0, current_health: 0 }
        ]
      },
      right: { player_id: "x", combatants: [] }
    }

    Sim::Campaign::BattleAftermath.apply!(campaign: campaign, battles: [ battle ], rng: rng)
    hero = player[:roster].first
    assert_equal 3, hero.dig(:state, :current_health)
    assert_equal false, hero.dig(:state, :is_routing)
  end

  test "non-general hero dies only on 1 in 36" do
    player = {
      id: "player-1",
      roster: [
        {
          id: "hero-2",
          kind: "hero",
          components: {
            formation: { models: 1, frontage: 1, max_files: 5, model_width: 1, model_depth: 1 },
            health: { model_health: 2, max: 2, permanent_losses: 0 },
            hero: { mounted: false, general: false }
          },
          state: { current_health: 0, is_routing: false }
        }
      ]
    }
    campaign = campaign_for(player)

    always_one = Object.new
    always_one.define_singleton_method(:rand) { |_max| 0 }
    battle = {
      left: {
        player_id: "player-1",
        combatants: [ { entity_id: "hero-2", starting_models: 1, models_remaining: 0, current_health: 0 } ]
      },
      right: { player_id: "x", combatants: [] }
    }
    Sim::Campaign::BattleAftermath.apply!(campaign: campaign, battles: [ battle ], rng: always_one)
    assert_empty player[:roster]

    player[:roster] = [
      {
        id: "hero-2",
        kind: "hero",
        components: {
          formation: { models: 1, frontage: 1, max_files: 5, model_width: 1, model_depth: 1 },
          health: { model_health: 2, max: 2, permanent_losses: 0 },
          hero: { mounted: false, general: false }
        },
        state: { current_health: 0, is_routing: false }
      }
    ]
    never_one = Object.new
    never_one.define_singleton_method(:rand) { |_max| 1 }
    Sim::Campaign::BattleAftermath.apply!(campaign: campaign, battles: [ battle ], rng: never_one)
    hero = player[:roster].first
    assert_equal 0, hero.dig(:state, :current_health)
  end

  private

  def campaign_for(player)
    campaign = Object.new
    campaign.define_singleton_method(:find_player) { |_id| player }
    campaign
  end

  def unit_player(models:, current_health:)
    {
      id: "player-1",
      roster: [
        {
          id: "unit-1",
          kind: "unit",
          components: {
            formation: { models: models, frontage: 5, max_files: 5, model_width: 1, model_depth: 1 },
            health: { model_health: 1, max: models, permanent_losses: 0 }
          },
          state: { current_health: current_health, is_routing: false }
        }
      ]
    }
  end

  def unit_battle(starting_models:, models_remaining:, current_health:)
    {
      left: {
        player_id: "player-1",
        combatants: [
          { entity_id: "unit-1", starting_models: starting_models, models_remaining: models_remaining, current_health: current_health }
        ]
      },
      right: { player_id: "player-2", combatants: [] }
    }
  end
end
