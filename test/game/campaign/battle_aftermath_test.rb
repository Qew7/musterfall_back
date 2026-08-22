require "test_helper"

class SimCampaignBattleAftermathTest < ActiveSupport::TestCase
  test "permanent death on roll of 1 reduces max models" do
    player = {
      id: "player-1",
      roster: [
        {
          id: "unit-1",
          kind: "unit",
          components: {
            formation: { models: 10, frontage: 5, max_files: 5, model_width: 1, model_depth: 1 },
            health: { model_health: 1, max: 10, permanent_losses: 0 }
          },
          state: { current_health: 10, is_routing: false }
        }
      ]
    }
    campaign = Object.new
    campaign.define_singleton_method(:find_player) { |_id| player }

    rng = Object.new
    rng.define_singleton_method(:rand) { |_max| 0 }

    battle = {
      left: {
        player_id: "player-1",
        combatants: [
          { entity_id: "unit-1", starting_models: 10, models_remaining: 6, current_health: 6 }
        ]
      },
      right: { player_id: "player-2", combatants: [] }
    }

    Sim::Campaign::BattleAftermath.apply!(campaign: campaign, battles: [ battle ], rng: rng)
    entity = player[:roster].first
    assert_equal 4, entity.dig(:components, :health, :permanent_losses)
    assert_equal 6, entity.dig(:components, :formation, :models)
    assert_equal 6, entity.dig(:state, :current_health)
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
    campaign = Object.new
    campaign.define_singleton_method(:find_player) { |_id| player }
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
    assert_equal 0, hero.dig(:components, :health, :permanent_losses)
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
    campaign = Object.new
    campaign.define_singleton_method(:find_player) { |_id| player }

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
    assert_equal 0, hero.dig(:components, :health, :permanent_losses)
  end
end
