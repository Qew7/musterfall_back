module Games
  # Re-run every RoundMatchup of a round with the same seeds.
  # Original matchup payloads stay; each replay is a new Battle row.
  class ReplayBattle
    def self.call(game:, matchup_id: nil, round_number: nil, left_player_id: nil, right_player_id: nil)
      new(
        game: game,
        matchup_id: matchup_id,
        round_number: round_number,
        left_player_id: left_player_id,
        right_player_id: right_player_id
      ).call
    end

    def initialize(game:, matchup_id:, round_number:, left_player_id:, right_player_id:)
      @game = game
      @matchup_id = matchup_id
      @round_number = round_number
      @left_player_id = left_player_id
      @right_player_id = right_player_id
    end

    def call
      matchups = find_matchups!
      payloads = matchups.map { |matchup| replay_payload(matchup) }

      persisted = ActiveRecord::Base.transaction do
        payloads.map do |matchup, fresh|
          battle = Sim::Persistence::BattleWriter.persist!(
            @game,
            fresh,
            round_number: matchup.campaign_round,
            as_new: true
          )
          [ matchup, fresh, battle ]
        end
      end

      battles = persisted.map { |matchup, fresh, battle| present(matchup, fresh, battle) }
      focused = focused_battle(battles)
      Sim::Result.ok(battle: focused, battles: battles)
    rescue ActiveRecord::RecordNotFound
      Sim::Result.failure("matchup not found")
    rescue ArgumentError => error
      Sim::Result.failure(error.message)
    end

    private

    def find_matchups!
      scope = @game.round_matchups
      if @matchup_id.present?
        seed = scope.find(@matchup_id)
        return scope.where(campaign_round: seed.campaign_round).order(:position).to_a
      end

      raise ArgumentError, "round_number, left_player_id and right_player_id are required" if [
        @round_number, @left_player_id, @right_player_id
      ].any?(&:blank?)

      round_scope = scope.where(campaign_round: @round_number)
      raise ActiveRecord::RecordNotFound, "RoundMatchup" unless round_scope.find { |row|
        [ row.attacker_player_key, row.defender_player_key ].sort ==
          [ @left_player_id, @right_player_id ].sort
      }

      round_scope.order(:position).to_a
    end

    def replay_payload(matchup)
      [ matchup, Sim::Battle::Replay.call(matchup: matchup, compare: false)[:result] ]
    end

    def present(matchup, fresh, battle)
      payload = camelize_battle(fresh.merge(matchup_id: matchup.id, seed: matchup.seed, battle_id: battle.id))
      payload[:terrain] = camelize_terrain(fresh[:terrain])
      payload
    end

    def focused_battle(battles)
      if @matchup_id.present?
        battles.find { |battle| battle["matchupId"].to_s == @matchup_id.to_s } || battles.first
      elsif @left_player_id.present?
        battles.find { |battle|
          [ battle.dig("left", "playerId"), battle.dig("right", "playerId") ].sort ==
            [ @left_player_id, @right_player_id ].sort
        } || battles.first
      else
        battles.first
      end
    end

    def camelize_battle(report)
      Sim::Campaign::State.new(round: 1, players: []).send(:deep_camelize, report.deep_symbolize_keys)
    end

    def camelize_terrain(features)
      Array(features).map do |feature|
        entry = feature.deep_symbolize_keys
        {
          id: entry[:id],
          type: entry[:type],
          x: entry[:x],
          y: entry[:y],
          width: entry[:width],
          depth: entry[:depth],
          impassable: entry[:impassable],
          blocksLos: entry[:blocks_los],
          moveCost: entry[:move_cost]
        }
      end
    end
  end
end
