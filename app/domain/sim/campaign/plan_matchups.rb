module Sim
  module Campaign
    # Build independent matchup specs for a round (no simulation).
    # Each matchup gets its own deterministic seed so battles can run in parallel.
    class PlanMatchups
      def self.call(campaign:, catalog:, rng_seed:)
        new(campaign, catalog, rng_seed).call
      end

      def initialize(campaign, catalog, rng_seed)
        @campaign = campaign.deep_dup
        @catalog = catalog
        @rng_seed = rng_seed.to_i
      end

      def call
        active_players = @campaign.players.select { |player| player[:status] == "active" }
        return Result.ok(campaign: @campaign, matchups: [], byes: []) if active_players.length <= 1

        active_players.each { |player| ensure_deployment!(player) }

        matchups = []
        byes = []
        position = 0

        bracket_queues(active_players).each do |queue|
          while queue.length > 1
            attacker = queue.shift
            defender = queue.shift
            position += 1
            matchups << {
              position: position,
              seed: battle_seed(position),
              attacker: attacker.deep_dup,
              defender: defender.deep_dup
            }
          end

          next unless queue.length == 1

          bye_player = queue.first
          byes << { player_id: bye_player[:id], player_name: bye_player[:name] }
        end

        Result.ok(campaign: @campaign, matchups: matchups, byes: byes)
      end

      private

      def bracket_queues(active_players)
        winner_ids = last_round_winner_ids
        return [ active_players.dup ] if winner_ids.empty?

        winners = []
        rest = []
        active_players.each do |player|
          (winner_ids.include?(player[:id]) ? winners : rest) << player
        end
        [ winners, rest ].reject(&:empty?)
      end

      def last_round_winner_ids
        Array(@campaign.last_round_report&.dig(:matchups)).filter_map { |battle| battle[:winner_id] }.to_set
      end

      def battle_seed(position)
        # Stable per (campaign version context is applied by caller via rng_seed).
        (@rng_seed + (@campaign.round * 1_000_003) + (position * 97)) & 0x7FFFFFFF
      end

      def ensure_deployment!(player)
        deployable = player[:roster].select { |entry| entry.dig(:state, :current_health).to_i > 0 }
        visible = deployable.select do |entry|
          Entities::Footprint.deployable?(entry) || (entry[:kind] == "hero" && entry[:state][:attached_to])
        end
        return if visible.any?

        result = Deploy.call(campaign: @campaign, player_id: player[:id], action: "auto")
        @campaign = result.value if result.ok?
      end
    end
  end
end
