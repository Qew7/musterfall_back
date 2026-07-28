module Api
  class BattlesController < ApplicationController
    include BattlePersistence

    before_action :ensure_replay_enabled!, only: :replay

    def create
      game = Game.find(params[:game_id])
      battle = nil

      ActiveRecord::Base.transaction do
        battle = persist_battle!(game, battle_payload)
      end

      render json: serialize_battle(battle.reload), status: :created
    end

    def replay
      game = Game.find(params[:game_id])
      result = Games::ReplayBattle.call(
        game: game,
        matchup_id: replay_params[:matchup_id],
        round_number: replay_params[:round_number],
        left_player_id: replay_params[:left_player_id],
        right_player_id: replay_params[:right_player_id]
      )
      return render json: { error: result.error }, status: :unprocessable_entity if result.failure?

      render json: result.value
    end

    private

    def ensure_replay_enabled!
      return if Rails.env.development? || Rails.env.test?

      render json: { error: "battle replay is only available in development" }, status: :not_found
    end

    def replay_params
      params.permit(:matchup_id, :round_number, :left_player_id, :right_player_id).to_h.symbolize_keys
    end

    def battle_params
      params.require(:battle).permit(*battle_attribute_schema)
    end

    def battle_payload
      normalize_battle_payload(battle_params)
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
                    events: battle_phase.events,
                    actions: battle_phase.actions
                  }
                end
              }
            end
          }
        end,
        createdAt: battle.created_at.iso8601,
        updatedAt: battle.updated_at.iso8601
      }
    end
  end
end
