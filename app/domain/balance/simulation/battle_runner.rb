module Balance
  module Simulation
    module BattleRunner
      MAX_FAILURES = 5

      module_function

      def run_sync!(run_id)
        run = BalanceSimulationRun.find(run_id)
        return if run.status.in?(%w[stopped completed failed])

        if run.stopping?
          run.update!(status: "stopped", finished_at: Time.current)
          return
        end

        return unless run.pending? || run.running?

        mark_running!(run)
        catalog = Sim::Catalog::Loader.load
        rng = Sim::Rng::Seeded.new(run.seed)

        loop do
          run.reload
          break if run.stopping? || run.status == "stopped"
          break if run.limit_reached?

          play_one_battle!(run, catalog, rng: rng)
        end

        finalize!(run)
      end

      def run_worker!(run_id)
        run = BalanceSimulationRun.find(run_id)
        return if run.status.in?(%w[stopped completed failed])

        mark_running!(run)
        catalog = Sim::Catalog::Loader.load

        loop do
          run.reload
          break if run.status.in?(%w[stopped completed failed])
          break if run.stopping?
          break if run.limit_reached?

          slot = claim_battle_slot!(run)
          break unless slot

          battle_no, rng = slot
          play_one_battle!(run, catalog, rng: rng)
        end
      ensure
        worker_finished!(run) if run
      end

      def mark_running!(run)
        run.with_lock do
          run.reload
          return unless run.pending? || run.running?

          run.update!(status: "running", started_at: run.started_at || Time.current, error_message: nil)
        end
      end

      def claim_battle_slot!(run)
        run.with_lock do
          run.reload
          return nil if run.status.in?(%w[stopped completed failed])
          return nil if run.stopping?
          return nil if run.limit_reached?

          config = run.config.deep_dup
          dispatched = config.fetch("battles_dispatched", 0)
          limit = run.battle_limit
          return nil if limit && dispatched >= limit

          config["battles_dispatched"] = dispatched + 1
          run.update!(config: config)
          [ dispatched, Sim::Rng::Seeded.new(run.seed + dispatched) ]
        end
      end

      def play_one_battle!(run, catalog, rng:)
        Balance::Synthetic::Play.call!(run: run, catalog: catalog, rng: rng)
        run.increment!(:battles_completed)
      rescue StandardError => error
        run.increment!(:battles_failed)
        run.update!(error_message: error.message)
        run.update!(status: "failed", finished_at: Time.current) if run.battles_failed >= MAX_FAILURES
      end

      def finalize!(run)
        run.reload
        return if run.status.in?(%w[stopped failed])

        final_status = run.stopping? ? "stopped" : "completed"
        run.update!(status: final_status, finished_at: Time.current)
      end

      def worker_finished!(run)
        run.with_lock do
          run.reload
          config = run.config.deep_dup
          finished = config.fetch("workers_finished", 0) + 1
          total = config.fetch("workers_total", 1)
          config["workers_finished"] = finished
          run.update!(config: config)
          return if finished < total
          return if run.status.in?(%w[stopped failed])

          final_status = run.stopping? ? "stopped" : "completed"
          run.update!(status: final_status, finished_at: Time.current)
        end
      end
    end
  end
end
