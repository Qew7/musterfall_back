module Api
  class GamesController < ApplicationController
    def create
      game = Game.create!(create_game_params)

      render json: serialize_game(game), status: :created
    end

    def show
      game = Game.includes(battles: { battle_rounds: { battle_turns: :battle_phases } }, round_snapshots: []).find(params[:id])

      render json: serialize_game(game, include_snapshots: true)
    end

    def update
      game = Game.find(params[:id])
      game.update!(update_game_params)

      render json: serialize_game(game)
    end

    private

    def create_game_params
      {
        player_count: game_payload.fetch(:player_count),
        current_round: game_payload[:current_round] || 1,
        status: game_payload[:status] || "draft",
        state_payload: game_payload[:state_payload] || {}
      }
    end

    def update_game_params
      game_payload.slice(:status, :current_round, :state_payload).to_h.compact
    end

    def game_payload
      params.expect(game: [:player_count, :current_round, :status, state_payload: {}])
    end

    def serialize_game(game, include_snapshots: false)
      payload = {
        id: game.id,
        status: game.status,
        playerCount: game.player_count,
        currentRound: game.current_round,
        statePayload: game.state_payload,
        battles: game.battles.map { |battle| serialize_battle(battle) }
      }

      if include_snapshots
        payload[:snapshots] = game.round_snapshots.map { |snapshot| serialize_snapshot(snapshot) }
      end

      payload
    end

    def serialize_snapshot(snapshot)
      {
        id: snapshot.id,
        roundNumber: snapshot.round_number,
        phase: snapshot.phase,
        payload: snapshot.payload,
        createdAt: snapshot.created_at.iso8601
      }
    end

    def serialize_battle(battle)
      {
        id: battle.id,
        roundNumber: battle.round_number,
        leftPlayerId: battle.left_player_id,
        leftPlayerName: battle.left_player_name,
        rightPlayerId: battle.right_player_id,
        rightPlayerName: battle.right_player_name,
        winnerId: battle.winner_id,
        winnerName: battle.winner_name,
        summary: battle.summary,
        left: battle.left_payload,
        right: battle.right_payload,
        events: battle.events,
        rounds: battle.battle_rounds.map do |battle_round|
          {
            id: battle_round.id,
            number: battle_round.number,
            events: battle_round.events,
            turns: battle_round.battle_turns.map do |battle_turn|
              {
                id: battle_turn.id,
                position: battle_turn.position,
                playerId: battle_turn.player_id,
                playerName: battle_turn.player_name,
                phases: battle_turn.battle_phases.map do |battle_phase|
                  {
                    id: battle_phase.id,
                    position: battle_phase.position,
                    type: battle_phase.phase_type,
                    label: battle_phase.label,
                    events: battle_phase.events
                  }
                end
              }
            end
          }
        end
      }
    end
  end
end