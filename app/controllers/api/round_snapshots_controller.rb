module Api
  class RoundSnapshotsController < ApplicationController
    def create
      game = Game.find(params[:game_id])
      snapshot = game.round_snapshots.find_or_initialize_by(
        round_number: snapshot_payload.fetch(:round_number),
        phase: snapshot_payload.fetch(:phase)
      )
      snapshot.payload = snapshot_payload.fetch(:payload)
      snapshot.save!

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
      params.expect(round_snapshot: [:round_number, :phase, payload: {}])
    end
  end
end