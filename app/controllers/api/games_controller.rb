module Api
  class GamesController < ApplicationController
    def create
      result = Games::CreateGame.call(player_count: create_params.fetch(:player_count))
      return render_failure(result) if result.failure?

      render json: serialize_game(result.value, include_campaign: true), status: :created
    end

    def show
      game = Game.includes(
        :game_players,
        battles: { battle_rounds: { battle_turns: :battle_phases } },
        round_snapshots: []
      ).find(params[:id])

      render json: serialize_game(game, include_campaign: true, include_snapshots: true)
    end

    def assign_faction
      apply_command(:assign_faction, %i[player_id faction_id school_key template_id])
    end

    def recruit
      apply_command(:recruit, %i[player_id template_id school_key])
    end

    def dismiss
      apply_command(:dismiss, %i[player_id entity_id])
    end

    def attach_hero
      apply_command(:attach_hero, %i[player_id hero_id unit_id])
    end

    def deploy
      apply_command(:deploy, %i[player_id deploy_mode entity_id x y facing direction])
    end

    def prepare_hero_draft
      apply_command(:prepare_hero_draft, %i[player_id hero_id])
    end

    def pick_hero_draft
      apply_command(:pick_hero_draft, %i[player_id hero_id upgrade_id])
    end

    def upgrade_access
      apply_command(:upgrade_access, %i[player_id])
    end

    def restore_unit
      apply_command(:restore_unit, %i[player_id entity_id models])
    end

    def prepare_round
      apply_command(:prepare_round, [])
    end

    def advance_round
      game = Game.find(params[:id])
      result = Games::AdvanceRound.call(game: game, base_version: command_params[:base_version])
      return render_failure(result, game: game) if result.failure?

      payload = result.value
      campaign_hash = payload[:campaign].to_api_hash
      campaign_hash[:terrain] = serialize_terrain(payload[:game], payload[:campaign].round)
      render json: {
        gameId: payload[:game].id,
        version: payload[:campaign].version,
        campaign: campaign_hash,
        metaReward: camelize_meta(payload[:meta_reward]),
        battles: payload[:battles].map { |battle| serialize_battle(battle) }
      }
    end

    private

    def apply_command(command, keys)
      game = Game.find(params[:id])
      result = Games::ApplyCommand.call(
        game: game,
        command: command,
        base_version: command_params[:base_version],
        params: command_params.slice(*keys)
      )
      return render_failure(result, game: game) if result.failure?

      payload = result.value
      campaign_hash = payload[:campaign].to_api_hash
      campaign_hash[:terrain] = serialize_terrain(game, payload[:campaign].round)
      render json: {
        gameId: payload[:game].id,
        version: payload[:campaign].version,
        campaign: campaign_hash
      }
    end

    def render_failure(result, game: nil)
      status = result.code == :conflict ? :conflict : :unprocessable_entity
      body = { error: result.error }
      if result.code == :conflict && game
        campaign = Sim::Persistence::CampaignRepository.new.load(game)
        campaign_hash = campaign.to_api_hash
        campaign_hash[:terrain] = serialize_terrain(game, campaign.round)
        body[:version] = campaign.version
        body[:campaign] = campaign_hash
      end
      render json: body, status: status
    end

    def create_params
      params.expect(game: [ :player_count ]).to_h.symbolize_keys
    end

    def command_params
      raw = params.permit(
        :base_version,
        :player_id,
        :faction_id,
        :school_key,
        :template_id,
        :entity_id,
        :hero_id,
        :unit_id,
        :upgrade_id,
        :models,
        :deploy_mode,
        :x,
        :y,
        :facing,
        :direction,
        command: {}
      ).to_h.symbolize_keys

      nested = raw.delete(:command)
      raw.merge!(nested.to_h.symbolize_keys) if nested.present?
      raw[:base_version] = raw[:base_version].to_i
      raw
    end

    def serialize_game(game, include_campaign: false, include_snapshots: false)
      payload = {
        id: game.id,
        status: game.status,
        playerCount: game.player_count,
        currentRound: game.current_round,
        version: game.campaign_version,
        battles: game.battles.map { |battle| serialize_battle(battle) }
      }

      if include_campaign
        campaign = Sim::Persistence::CampaignRepository.new.load(game)
        campaign_hash = campaign.to_api_hash
        campaign_hash[:terrain] = serialize_terrain(game, campaign.round)
        payload[:campaign] = campaign_hash
        payload[:statePayload] = { campaign: campaign_hash }
      end

      if include_snapshots
        payload[:snapshots] = game.round_snapshots.map { |snapshot| serialize_snapshot(snapshot) }
      end

      payload
    end

    def serialize_terrain(game, round)
      seed = Sim::Battle::TerrainMap.map_seed(rng_seed: game.rng_seed, round: round)
      features = Sim::Battle::TerrainMap.generate(seed: seed)
      features.map { |feature| camelize_terrain_feature(feature) }
    end

    def camelize_terrain_feature(feature)
      {
        id: feature[:id],
        type: feature[:type],
        x: feature[:x],
        y: feature[:y],
        width: feature[:width],
        depth: feature[:depth],
        impassable: feature[:impassable],
        blocksLos: feature[:blocks_los],
        moveCost: feature[:move_cost]
      }
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
                    events: battle_phase.events,
                    actions: battle_phase.actions
                  }
                end
              }
            end
          }
        end
      }
    end

    def camelize_meta(meta)
      return nil unless meta

      {
        playerId: meta[:player_id],
        playerName: meta[:player_name],
        factionId: meta[:faction_id],
        experience: meta[:experience],
        essence: meta[:essence]
      }
    end
  end
end
