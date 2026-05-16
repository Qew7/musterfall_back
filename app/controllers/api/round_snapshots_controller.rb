module Api
  class RoundSnapshotsController < ApplicationController
    include BattlePersistence

    def create
      game = Game.find(params[:game_id])
      snapshot = nil

      ActiveRecord::Base.transaction do
        snapshot = game.round_snapshots.find_or_initialize_by(
          round_number: snapshot_payload.fetch(:round_number),
          phase: snapshot_payload.fetch(:phase)
        )
        snapshot.payload = snapshot_payload.fetch(:payload)
        snapshot.save!

        Array(snapshot_payload[:battles]).each do |battle_payload|
          persist_battle!(game, battle_payload)
        end
      end

      render json: {
        id: snapshot.id,
        roundNumber: snapshot.round_number,
        phase: snapshot.phase,
        payload: snapshot.payload,
        createdAt: snapshot.created_at.iso8601,
        updatedAt: snapshot.updated_at.iso8601
      }, status: :created
    end

    private

    def snapshot_payload
      payload = params.require(:round_snapshot).permit(
        :round_number,
        :phase,
        { payload: {} },
        { battles: battle_attribute_schema }
      ).to_h.deep_symbolize_keys

      payload[:round_number] = Integer(payload.fetch(:round_number))
      payload[:payload] = payload.fetch(:payload)
      payload[:battles] = Array(payload[:battles]).map { |battle_payload| normalize_battle_payload(battle_payload) }
      payload[:battles] = enrich_battle_payloads_from_snapshot_state(payload[:battles], payload[:payload])
      payload
    end
  end
end
