module Games
  # Re-run a stored RoundMatchup in memory (no DB writes) for dev replay testing.
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
      matchup = find_matchup!
      fresh = Sim::Battle::Replay.call(matchup: matchup, compare: false)[:result]
      battle = camelize_battle(
        fresh.merge(matchup_id: matchup.id, seed: matchup.seed)
      )
      battle[:terrain] = camelize_terrain(fresh[:terrain])

      Sim::Result.ok(battle: battle)
    rescue ActiveRecord::RecordNotFound
      Sim::Result.failure("matchup not found")
    rescue ArgumentError => error
      Sim::Result.failure(error.message)
    end

    private

    def find_matchup!
      if @matchup_id.present?
        @game.round_matchups.find(@matchup_id)
      else
        raise ArgumentError, "round_number, left_player_id and right_player_id are required" if [
          @round_number, @left_player_id, @right_player_id
        ].any?(&:blank?)

        matchup = @game.round_matchups.where(campaign_round: @round_number).find do |row|
          [ row.attacker_player_key, row.defender_player_key ].sort ==
            [ @left_player_id, @right_player_id ].sort
        end
        raise ActiveRecord::RecordNotFound, "RoundMatchup" unless matchup

        matchup
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
