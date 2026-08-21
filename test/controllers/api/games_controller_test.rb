require "test_helper"

class Api::GamesControllerTest < ActionDispatch::IntegrationTest
  test "assign faction accepts a starter wizard school and returns its authoritative loadout" do
    post "/api/games", params: { game: { player_count: 2 } }
    game_id = response.parsed_body.fetch("id")
    faction_id = catalog.factions.find do |faction|
      catalog.hero_templates(faction[:id]).first&.dig(:abilities)&.include?("wizard")
    end[:id]

    with_spell_api(
      schools: %i[necromancy shadow],
      spell_keys: %i[raise_dead soul_drain grave_call]
    ) do
      post "/api/games/#{game_id}/assign_faction", params: {
        base_version: 0,
        player_id: "player-1",
        faction_id: faction_id,
        school_key: "necromancy"
      }
    end

    assert_response :success
    hero = response.parsed_body.dig("campaign", "players", 0, "roster", 0, "components", "hero")
    assert_equal "necromancy", hero.fetch("magicSchool")
    assert_equal 2, hero.fetch("spellKeys").uniq.length
  end

  test "recruit accepts a wizard school and returns its authoritative loadout" do
    faction = catalog.factions.find do |entry|
      heroes = catalog.hero_templates(entry[:id])
      !heroes.first&.dig(:abilities)&.include?("wizard") && heroes.any? { |hero| hero[:abilities].include?("wizard") }
    end
    wizard = catalog.hero_templates(faction[:id]).find { |hero| hero[:abilities].include?("wizard") }
    post "/api/games", params: { game: { player_count: 2 } }
    game_id = response.parsed_body.fetch("id")
    post "/api/games/#{game_id}/assign_faction", params: {
      base_version: 0,
      player_id: "player-1",
      faction_id: faction[:id]
    }

    with_spell_api(
      schools: %i[pyromancy celestial],
      spell_keys: %i[fireball inferno cinder_shield]
    ) do
      post "/api/games/#{game_id}/recruit", params: {
        base_version: 1,
        player_id: "player-1",
        template_id: wizard[:id],
        school_key: "pyromancy"
      }
    end

    assert_response :success
    hero = response.parsed_body.dig("campaign", "players", 0, "roster").last
    assert_equal "pyromancy", hero.dig("components", "hero", "magicSchool")
    assert_equal 2, hero.dig("components", "hero", "spellKeys").uniq.length
  end

  test "stores nested battle reports in the same snapshot request" do
    post "/api/games", params: {
      game: {
        player_count: 4,
        current_round: 1,
        status: "active",
        state_payload: { players: [] }
      }
    }

    assert_response :created

    payload = response.parsed_body
    game_id = payload.fetch("id")

    post "/api/games/#{game_id}/round_snapshots", params: {
      round_snapshot: {
        round_number: 1,
        phase: "pre_round",
        payload: { armies: [] },
        battles: [ battle_payload ]
      }
    }

    assert_response :created

    get "/api/games/#{game_id}"

    assert_response :success

    game_payload = response.parsed_body
    assert_equal 1, game_payload.fetch("battles").size
    assert_equal 1, game_payload.fetch("snapshots").size
    phase_payload = game_payload.fetch("battles").first.fetch("rounds").first.fetch("turns").first.fetch("phases").first

    assert_equal "movement", phase_payload.fetch("type")
    assert_equal 1, phase_payload.fetch("actions").size
    assert_equal "Копейщики выдвигается в ряд support.", phase_payload.fetch("actions").first.fetch("summary")
    assert_equal 12, phase_payload.fetch("actions").first.fetch("actor_state_before").fetch("models_remaining")
    assert_equal "Копейщики до движения: rear/left, facing 0, HP 24/24, моделей 12", phase_payload.fetch("actions").first.fetch("details").first
  end

  test "rolls back snapshot when nested battle report is invalid" do
    post "/api/games", params: {
      game: {
        player_count: 4,
        current_round: 1,
        status: "active",
        state_payload: { players: [] }
      }
    }

    assert_response :created

    game_id = response.parsed_body.fetch("id")

    assert_no_difference [ "RoundSnapshot.count", "Battle.count" ] do
      post "/api/games/#{game_id}/round_snapshots", params: {
        round_snapshot: {
          round_number: 1,
          phase: "post_round",
          payload: { armies: [] },
          battles: [ battle_payload.merge(rounds: [ { number: 1, events: [], turns: [ { position: 0, player_id: "player-1", player_name: "Полководец 1", phases: [ { position: 0, phase_type: "invalid", label: "Ошибка", events: [] } ] } ] } ]) ]
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "fills detailed battle actions from snapshot campaign report when explicit battles are stale" do
    post "/api/games", params: {
      game: {
        player_count: 4,
        current_round: 1,
        status: "active",
        state_payload: { players: [] }
      }
    }

    assert_response :created

    game_id = response.parsed_body.fetch("id")

    stale_battle_payload = battle_payload.deep_dup
    stale_battle_payload[:rounds][0][:turns][0][:phases].each { |phase| phase[:actions] = [] }
    stale_battle_payload[:rounds][0][:turns][0][:phases][0][:events] = [ "Отряд выдвигается" ]

    post "/api/games/#{game_id}/round_snapshots", params: {
      round_snapshot: {
        round_number: 1,
        phase: "post_round",
        payload: {
          campaign: {
            round: 2,
            lastRoundReport: {
              round: 1,
              matchups: [ snapshot_report_battle ]
            }
          }
        },
        battles: [ stale_battle_payload ]
      }
    }

    assert_response :created

    get "/api/games/#{game_id}"

    assert_response :success

    action_payload = response.parsed_body.fetch("battles").first.fetch("rounds").first.fetch("turns").first.fetch("phases").first.fetch("actions").first
    assert_equal "Копейщики выдвигается в ряд support.", action_payload.fetch("summary")
    assert_equal 12, action_payload.fetch("actor_state_before").fetch("models_remaining")
  end

  private

  def battle_payload
    {
      round_number: 1,
      left_player_id: "player-1",
      left_player_name: "Полководец 1",
      right_player_id: "player-2",
      right_player_name: "Полководец 2",
      winner_id: "player-1",
      winner_name: "Полководец 1",
      summary: "Полководец 1 10 vs 0 Полководец 2",
      left_payload: { playerId: "player-1", combatants: [] },
      right_payload: { playerId: "player-2", combatants: [] },
      events: [ "Раунд 1" ],
      rounds: [
        {
          number: 1,
          events: [ "Пассивка сработала" ],
          turns: [
            {
              position: 0,
              player_id: "player-1",
              player_name: "Полководец 1",
              phases: [
                {
                  position: 0,
                  phase_type: "movement",
                  label: "Фаза движения",
                  events: [ "Отряд выдвигается" ],
                  actions: [
                    {
                      type: "movement",
                      summary: "Копейщики выдвигается в ряд support.",
                      details: [
                        "Копейщики до движения: rear/left, facing 0, HP 24/24, моделей 12",
                        "Маршрут: (1.0, 2.0) -> (1.5, 2.5)",
                        "Копейщики после движения: support/left, facing 0, HP 24/24, моделей 12"
                      ],
                      actor_id: "unit-1",
                      actor_name: "Копейщики",
                      from: { x: 1.0, y: 2.0, facing: 0, row: "rear", lane: "left" },
                      to: { x: 1.5, y: 2.5, facing: 0, row: "support", lane: "left" },
                      actor_state_before: {
                        entity_id: "unit-1",
                        name: "Копейщики",
                        kind: "unit",
                        side_key: "left",
                        lane: "left",
                        row: "rear",
                        x: 1.0,
                        y: 2.0,
                        facing: 0,
                        current_health: 24,
                        max_health: 24,
                        model_health: 2,
                        models_remaining: 12,
                        frontage: 4,
                        max_files: 4,
                        files: 4,
                        ranks: 3,
                        base_width: 4.0,
                        base_depth: 3.0,
                        movement: 3,
                        melee: 4,
                        ranged: 0,
                        spell: 0,
                        armor_type: "medium",
                        weapon_type: "pierce",
                        attached_heroes: []
                      },
                      actor_state_after: {
                        entity_id: "unit-1",
                        name: "Копейщики",
                        kind: "unit",
                        side_key: "left",
                        lane: "left",
                        row: "support",
                        x: 1.5,
                        y: 2.5,
                        facing: 0,
                        current_health: 24,
                        max_health: 24,
                        model_health: 2,
                        models_remaining: 12,
                        frontage: 4,
                        max_files: 4,
                        files: 4,
                        ranks: 3,
                        base_width: 4.0,
                        base_depth: 3.0,
                        movement: 3,
                        melee: 4,
                        ranged: 0,
                        spell: 0,
                        armor_type: "medium",
                        weapon_type: "pierce",
                        attached_heroes: []
                      }
                    }
                  ]
                },
                { position: 1, phase_type: "magic", label: "Фаза магии", events: [] },
                { position: 2, phase_type: "shooting", label: "Фаза стрельбы", events: [] },
                {
                  position: 3,
                  phase_type: "melee",
                  label: "Фаза боя",
                  events: [ "Нанесён урон" ],
                  actions: [
                    {
                      type: "melee",
                      summary: "Отряд Копейщики атакует Орки в фронт и наносит 5 урона.",
                      details: [
                        "Атакующий до удара: Копейщики HP 24/24, моделей 12, строй front/left, ряды 3, файлы 4",
                        "Цель до удара: Орки HP 18/18, моделей 9, строй front/left, ряды 3, файлы 3",
                        "Урон: 5, направление: фронт, затронуто целей: 1",
                        "Цель после удара: Орки HP 13/18, моделей 7, строй front/left, ряды 3, файлы 3"
                      ],
                      actor_id: "unit-1",
                      actor_unit_id: "unit-1",
                      actor_name: "Копейщики",
                      actor_role: "unit",
                      target_id: "unit-2",
                      target_name: "Орки",
                      vector: "front",
                      damage: 5,
                      blockers: [],
                      requires_line_of_sight: false,
                      affected_ids: [ "unit-2" ],
                      actor_state: {
                        entity_id: "unit-1",
                        name: "Копейщики",
                        kind: "unit",
                        side_key: "left",
                        lane: "left",
                        row: "front",
                        x: 1.5,
                        y: 2.5,
                        facing: 0,
                        current_health: 24,
                        max_health: 24,
                        model_health: 2,
                        models_remaining: 12,
                        frontage: 4,
                        max_files: 4,
                        files: 4,
                        ranks: 3,
                        base_width: 4.0,
                        base_depth: 3.0,
                        movement: 3,
                        melee: 4,
                        ranged: 0,
                        spell: 0,
                        armor_type: "medium",
                        weapon_type: "pierce",
                        attached_heroes: []
                      },
                      target_state_before: {
                        entity_id: "unit-2",
                        name: "Орки",
                        kind: "unit",
                        side_key: "right",
                        lane: "left",
                        row: "front",
                        x: 4.0,
                        y: 2.5,
                        facing: 180,
                        current_health: 18,
                        max_health: 18,
                        model_health: 2,
                        models_remaining: 9,
                        frontage: 3,
                        max_files: 3,
                        files: 3,
                        ranks: 3,
                        base_width: 3.0,
                        base_depth: 3.0,
                        movement: 3,
                        melee: 4,
                        ranged: 0,
                        spell: 0,
                        armor_type: "light",
                        weapon_type: "slash",
                        attached_heroes: []
                      },
                      target_state_after: {
                        entity_id: "unit-2",
                        name: "Орки",
                        kind: "unit",
                        side_key: "right",
                        lane: "left",
                        row: "front",
                        x: 4.0,
                        y: 2.5,
                        facing: 180,
                        current_health: 13,
                        max_health: 18,
                        model_health: 2,
                        models_remaining: 7,
                        frontage: 3,
                        max_files: 3,
                        files: 3,
                        ranks: 3,
                        base_width: 3.0,
                        base_depth: 3.0,
                        movement: 3,
                        melee: 4,
                        ranged: 0,
                        spell: 0,
                        armor_type: "light",
                        weapon_type: "slash",
                        attached_heroes: []
                      }
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  end

  def snapshot_report_battle
    {
      battleId: "battle-1",
      left: { playerId: "player-1", playerName: "Полководец 1", combatants: [] },
      right: { playerId: "player-2", playerName: "Полководец 2", combatants: [] },
      winnerId: "player-1",
      winnerName: "Полководец 1",
      summary: "Полководец 1 10 vs 0 Полководец 2",
      events: [ "Раунд 1" ],
      rounds: [
        {
          number: 1,
          events: [ "Пассивка сработала" ],
          turns: [
            {
              playerId: "player-1",
              playerName: "Полководец 1",
              phases: [
                {
                  type: "movement",
                  label: "Фаза движения",
                  events: [ "Отряд выдвигается" ],
                  actions: [
                    {
                      type: "movement",
                      summary: "Копейщики выдвигается в ряд support.",
                      details: [
                        "Копейщики до движения: rear/left, facing 0, HP 24/24, моделей 12"
                      ],
                      actorId: "unit-1",
                      actorName: "Копейщики",
                      actorStateBefore: {
                        entityId: "unit-1",
                        name: "Копейщики",
                        kind: "unit",
                        sideKey: "left",
                        lane: "left",
                        row: "rear",
                        x: 1.0,
                        y: 2.0,
                        facing: 0,
                        currentHealth: 24,
                        maxHealth: 24,
                        modelHealth: 2,
                        modelsRemaining: 12,
                        frontage: 4,
                        maxFiles: 4,
                        files: 4,
                        ranks: 3,
                        baseWidth: 4.0,
                        baseDepth: 3.0,
                        movement: 3,
                        melee: 4,
                        ranged: 0,
                        spell: 0,
                        armorType: "medium",
                        weaponType: "pierce",
                        attachedHeroes: []
                      },
                      actorStateAfter: {
                        entityId: "unit-1",
                        name: "Копейщики",
                        kind: "unit",
                        sideKey: "left",
                        lane: "left",
                        row: "support",
                        x: 1.5,
                        y: 2.5,
                        facing: 0,
                        currentHealth: 24,
                        maxHealth: 24,
                        modelHealth: 2,
                        modelsRemaining: 12,
                        frontage: 4,
                        maxFiles: 4,
                        files: 4,
                        ranks: 3,
                        baseWidth: 4.0,
                        baseDepth: 3.0,
                        movement: 3,
                        melee: 4,
                        ranged: 0,
                        spell: 0,
                        armorType: "medium",
                        weaponType: "pierce",
                        attachedHeroes: []
                      },
                      from: { x: 1.0, y: 2.0, facing: 0, row: "rear", lane: "left" },
                      to: { x: 1.5, y: 2.5, facing: 0, row: "support", lane: "left" }
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  end
end
