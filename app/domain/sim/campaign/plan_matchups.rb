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

        queue = active_players.dup
        matchups = []
        position = 0

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

        byes = []
        if queue.length == 1
          bye_player = queue.first
          byes << { player_id: bye_player[:id], player_name: bye_player[:name] }
        end

        Result.ok(campaign: @campaign, matchups: matchups, byes: byes)
      end

      private

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
