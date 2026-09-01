module Balance
  module Simulation
    module_function

    def start!(config:)
      version = CatalogVersion.current!
      workers = worker_count
      run = BalanceSimulationRun.create!(
        catalog_version: version,
        status: "pending",
        config: normalize_config(config).merge(
          workers_total: workers,
          workers_finished: 0,
          battles_dispatched: 0
        ),
        seed: SecureRandom.random_number(0x7FFFFFFF)
      )
      Runner.enqueue_simulation!(run.id, count: workers)
      run.update!(status: "running", started_at: Time.current)
      run
    end

    def stop!(run_id)
      run = BalanceSimulationRun.find(run_id)
      run.stop!
      run
    end

    def stop_all!
      runs = BalanceSimulationRun.active.order(created_at: :desc).to_a
      runs.each(&:stop!)
      runs
    end

    def worker_count
      Parallelism.worker_count
    end

    def normalize_config(raw)
      config = raw.deep_symbolize_keys
      if config[:preset].to_s == "balanced_random"
        return {
          battle_limit: config[:battle_limit].presence&.to_i,
          preset: "balanced_random",
          round: config[:round].to_i.clamp(1, Sim::Constants::MAX_CAMPAIGN_ROUNDS),
          budget_mode: config[:budget_mode].presence || "fixed",
          target_points: (config[:target_points].presence || 500).to_i.clamp(50, 5000),
          points_jitter: config[:points_jitter].to_i.clamp(0, 2000),
          hero_level: config[:hero_level].to_i.clamp(1, 6),
          randomize_hero_level: !!config[:randomize_hero_level]
        }.compact
      end

      {
        battle_limit: config[:battle_limit].presence&.to_i,
        round: config[:round].to_i.clamp(1, Sim::Constants::MAX_CAMPAIGN_ROUNDS),
        budget_mode: config[:budget_mode].presence || "fixed",
        target_points: (config[:target_points].presence || 500).to_i.clamp(50, 5000),
        points_jitter: config[:points_jitter].to_i.clamp(0, 2000),
        hero_level: config[:hero_level].to_i.clamp(1, 6),
        randomize_hero_level: !!config[:randomize_hero_level],
        faction_left: config[:faction_left].presence,
        faction_right: config[:faction_right].presence,
        recruit_strategy: config[:recruit_strategy].presence || "balanced"
      }.compact
    end
  end
end
