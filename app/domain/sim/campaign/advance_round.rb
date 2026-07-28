module Sim
  module Campaign
    class AdvanceRound
      def self.call(campaign:, catalog:, rng:)
        new(campaign, catalog, rng).call
      end

      def initialize(campaign, catalog, rng)
        @campaign = campaign
        @catalog = catalog
        @rng = rng
      end

      def call
        seed = @rng.rand(1_000_000_000)
        planned = PlanMatchups.call(campaign: @campaign, catalog: @catalog, rng_seed: seed)
        return planned if planned.failure?

        payload = planned.value
        battles = payload[:matchups].map do |matchup|
          map_seed = Battle::TerrainMap.map_seed(rng_seed: seed, round: payload[:campaign].round)
          Battle::Simulator.call(
            matchup[:attacker],
            matchup[:defender],
            @catalog,
            rng: Rng::Seeded.new(matchup[:seed]),
            map_seed: map_seed
          )
        end

        SettleMatchups.call(
          campaign: payload[:campaign],
          battles: battles,
          byes: payload[:byes]
        )
      end
    end
  end
end
