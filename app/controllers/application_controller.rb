class ApplicationController < ActionController::API
  after_action :audit_player_action, if: :audit_player_action?

  private

  def audit_player_action?
    request.post? && controller_path.start_with?("api/")
  end

  def audit_player_action
    payload = params.permit(
      :base_version, :player_id, :faction_id, :school_key, :template_id,
      :entity_id, :hero_id, :unit_id, :upgrade_id, :models, :deploy_mode,
      :x, :y, :facing, :direction, :matchup_id, :round_number,
      :left_player_id, :right_player_id,
      game: [ :player_count ],
      command: {}
    ).to_h

    PlayerAction.create(
      game_id: audit_game_id,
      action: "#{controller_name}##{action_name}",
      http_status: response.status,
      player_id: payload["player_id"] || payload[:player_id],
      params: payload,
      created_at: Time.current
    )
  rescue StandardError => error
    Rails.logger.error("player_action audit failed: #{error.class}: #{error.message}")
  end

  def audit_game_id
    id = params[:id].presence || params[:game_id].presence
    return id if id
    return unless action_name == "create" && response.successful?

    JSON.parse(response.body)["id"]
  rescue JSON::ParserError
    nil
  end
end
