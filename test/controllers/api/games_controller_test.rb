require "test_helper"

class Api::GamesControllerTest < ActionDispatch::IntegrationTest
  test "creates game, snapshots round and stores nested battle report" do
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

    post "/api/games/#{game_id}/battles", params: {
      battle: {
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
        events: ["Раунд 1"],
        rounds: [
          {
            number: 1,
            events: ["Пассивка сработала"],
            turns: [
              {
                position: 0,
                player_id: "player-1",
                player_name: "Полководец 1",
                phases: [
                  { position: 0, phase_type: "movement", label: "Фаза движения", events: ["Отряд выдвигается"] },
                  { position: 1, phase_type: "magic", label: "Фаза магии", events: [] },
                  { position: 2, phase_type: "shooting", label: "Фаза стрельбы", events: [] },
                  { position: 3, phase_type: "melee", label: "Фаза боя", events: ["Нанесён урон"] }
                ]
              }
            ]
          }
        ]
      }
    }

    assert_response :created

    battle_payload = response.parsed_body
    assert_equal 1, battle_payload.fetch("roundNumber")
    assert_equal "player-1", battle_payload.fetch("winnerId")
    assert_equal 1, battle_payload.fetch("rounds").size
    assert_equal 4, battle_payload.fetch("rounds").first.fetch("turns").first.fetch("phases").size

    post "/api/games/#{game_id}/round_snapshots", params: {
      round_snapshot: {
        round_number: 1,
        phase: "pre_round",
        payload: { armies: [] }
      }
    }

    assert_response :created

    get "/api/games/#{game_id}"

    assert_response :success

    game_payload = response.parsed_body
    assert_equal 1, game_payload.fetch("battles").size
    assert_equal 1, game_payload.fetch("snapshots").size
    assert_equal "movement", game_payload.fetch("battles").first.fetch("rounds").first.fetch("turns").first.fetch("phases").first.fetch("type")
  end
end