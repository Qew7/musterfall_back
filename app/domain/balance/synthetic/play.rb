module Balance
  module Synthetic
    module Play
      module_function

      RECRUIT_STRATEGIES = %w[balanced horde push_elite heroes].freeze

      def call!(run:, catalog:, rng:)
        config = effective_config(run.config.deep_symbolize_keys, rng)
        round = config[:round].to_i.clamp(1, Sim::Constants::MAX_CAMPAIGN_ROUNDS)
        left_faction, right_faction = pick_factions(catalog, config, rng)
        left_budget, right_budget = budgets_for(config, rng)
        hero_level = hero_level_for(config, rng)
        strategy = config[:recruit_strategy].presence || "balanced"

        left = Army.build!(
          catalog: catalog,
          faction_id: left_faction,
          budget: left_budget,
          hero_level: hero_level,
          rng: rng,
          player_id: "sim-left",
          recruit_strategy: strategy
        )
        right = Army.build!(
          catalog: catalog,
          faction_id: right_faction,
          budget: right_budget,
          hero_level: hero_level,
          rng: rng,
          player_id: "sim-right",
          recruit_strategy: strategy
        )

        battle_seed = rng.rand(0x7FFFFFFF)
        map_seed = Sim::Battle::TerrainMap.map_seed(rng_seed: run.seed, round: round)
        result = Sim::Battle::Simulator.call(
          left,
          right,
          catalog,
          rng: Sim::Rng::Seeded.new(battle_seed),
          map_seed: map_seed
        )

        Persist.call!(
          result: result,
          attacker: left,
          defender: right,
          catalog_version: run.catalog_version,
          source: "synthetic",
          balance_simulation_run_id: run.id,
          metrics_extra: {
            simulation_run_id: run.id,
            round: round,
            left_budget: left_budget,
            right_budget: right_budget,
            hero_level: hero_level,
            recruit_strategy: strategy
          }
        )
      end

      def pick_factions(catalog, config, rng)
        pool = catalog.factions.map { |entry| entry[:id] }
        left = config[:faction_left].presence || rng.pick(pool)
        right = config[:faction_right].presence || rng.pick(pool.reject { |entry| entry == left }.presence || pool)
        [ left, right ]
      end

      def budgets_for(config, rng)
        mode = config[:budget_mode].to_s.presence || "fixed"
        base = config[:target_points].to_i
        base = 500 if base <= 0
        jitter = config[:points_jitter].to_i

        case mode
        when "round_income"
          value = Sim::Constants.income_for(config[:round].to_i.clamp(1, Sim::Constants::MAX_CAMPAIGN_ROUNDS))
          [ value, value ]
        when "random"
          [ jitter_budget(base, jitter, rng), jitter_budget(base, jitter, rng) ]
        else
          [ base, base ]
        end
      end

      def jitter_budget(base, jitter, rng)
        return base if jitter <= 0

        base + rng.rand((jitter * 2) + 1) - jitter
      end

      def hero_level_for(config, rng)
        if config[:randomize_hero_level]
          rng.rand(4) + 1
        else
          config[:hero_level].to_i.clamp(1, 6)
        end
      end

      def effective_config(config, rng)
        return config unless config[:preset].to_s == "balanced_random"

        config.merge(
          faction_left: nil,
          faction_right: nil,
          recruit_strategy: rng.pick(RECRUIT_STRATEGIES)
        )
      end
    end
  end
end
