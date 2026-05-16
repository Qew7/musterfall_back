module Api
  class BattlesController < ApplicationController
    def create
      game = Game.find(params[:game_id])
      battle = game.battles.find_or_initialize_by(
        round_number: battle_payload.fetch(:round_number),
        left_player_id: battle_payload.fetch(:left_player_id),
        right_player_id: battle_payload.fetch(:right_player_id)
      )

      ActiveRecord::Base.transaction do
        assign_battle_attributes(battle, battle_payload)
        battle.save!
        replace_rounds!(battle, battle_payload.fetch(:rounds))
      end

      render json: serialize_battle(battle.reload), status: :created
    end

    private

    def battle_params
      params.require(:battle).permit(
        :round_number,
        :left_player_id,
        :left_player_name,
        :right_player_id,
        :right_player_name,
        :winner_id,
        :winner_name,
        :summary,
        :left_payload,
        :right_payload,
        events: [],
        left_payload: {},
        right_payload: {},
        rounds: [
          :number,
          { events: [] },
          { turns: [
            :position,
            :player_id,
            :player_name,
            { phases: [
              :position,
              :phase_type,
              :label,
              { events: [] }
            ] }
          ] }
        ]
      )
    end

    def battle_payload
      payload = battle_params.to_h.deep_symbolize_keys
      payload[:round_number] = Integer(payload.fetch(:round_number))
      payload[:events] = payload.fetch(:events)
      payload[:left_payload] = payload.fetch(:left_payload)
      payload[:right_payload] = payload.fetch(:right_payload)
      payload[:rounds] = Array(payload.fetch(:rounds)).map do |round_payload|
        normalized_round = round_payload.deep_symbolize_keys
        normalized_round[:number] = Integer(normalized_round.fetch(:number))
        normalized_round[:events] = normalized_round.fetch(:events)
        normalized_round[:turns] = Array(normalized_round.fetch(:turns)).map.with_index do |turn_payload, turn_index|
          normalized_turn = turn_payload.deep_symbolize_keys
          normalized_turn[:position] = Integer(normalized_turn[:position] || turn_index)
          normalized_turn[:phases] = Array(normalized_turn.fetch(:phases)).map.with_index do |phase_payload, phase_index|
            normalized_phase = phase_payload.deep_symbolize_keys
            normalized_phase[:position] = Integer(normalized_phase[:position] || phase_index)
            normalized_phase[:events] = normalized_phase.fetch(:events)
            normalized_phase
          end
          normalized_turn
        end
        normalized_round
      end
      payload
    end

    def assign_battle_attributes(battle, payload)
      battle.assign_attributes(
        left_player_name: payload.fetch(:left_player_name),
        right_player_name: payload.fetch(:right_player_name),
        winner_id: payload.fetch(:winner_id),
        winner_name: payload.fetch(:winner_name),
        summary: payload.fetch(:summary),
        left_payload: payload.fetch(:left_payload),
        right_payload: payload.fetch(:right_payload),
        events: payload.fetch(:events)
      )
    end

    def replace_rounds!(battle, rounds_payload)
      battle.battle_rounds.destroy_all

      rounds_payload.each do |round_payload|
        battle_round = battle.battle_rounds.create!(
          number: round_payload.fetch(:number),
          events: round_payload.fetch(:events)
        )

        Array(round_payload.fetch(:turns)).each do |turn_payload|
          battle_turn = battle_round.battle_turns.create!(
            position: turn_payload.fetch(:position),
            player_id: turn_payload.fetch(:player_id),
            player_name: turn_payload.fetch(:player_name)
          )

          Array(turn_payload.fetch(:phases)).each do |phase_payload|
            battle_turn.battle_phases.create!(
              position: phase_payload.fetch(:position),
              phase_type: phase_payload.fetch(:phase_type),
              label: phase_payload.fetch(:label),
              events: phase_payload.fetch(:events)
            )
          end
        end
      end
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
        end,
        createdAt: battle.created_at.iso8601,
        updatedAt: battle.updated_at.iso8601
      }
    end
  end
end