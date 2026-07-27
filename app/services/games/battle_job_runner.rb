module Games
  # Runs battle simulation jobs according to environment:
  # - inline (test / default development): perform_now, deterministic & no workers
  # - async (production / optional development): perform_later via Solid Queue, wait for completion
  module BattleJobRunner
    DEFAULT_TIMEOUT = 180

    module_function

    def run_all!(matchups, timeout: DEFAULT_TIMEOUT)
      ids = Array(matchups).map { |matchup| matchup.is_a?(RoundMatchup) ? matchup.id : matchup }
      return [] if ids.empty?

      if inline?
        ids.each { |id| SimulateBattleJob.perform_now(id) }
      else
        ids.each { |id| SimulateBattleJob.perform_later(id) }
        wait_until_finished!(ids, timeout: timeout)
      end

      RoundMatchup.where(id: ids).order(:position).to_a
    end

    def inline?
      mode = Rails.configuration.x.battle_jobs.execution_mode.to_sym
      return true if mode == :inline

      adapter = ActiveJob::Base.queue_adapter
      adapter.is_a?(ActiveJob::QueueAdapters::InlineAdapter) ||
        adapter.is_a?(ActiveJob::QueueAdapters::TestAdapter)
    end

    def wait_until_finished!(ids, timeout:)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        rows = RoundMatchup.where(id: ids).pluck(:id, :status, :error_message)
        statuses = rows.map { |(_, status, _)| status }

        if statuses.any? { |status| status == "failed" }
          message = rows.find { |(_, status, _)| status == "failed" }&.last || "battle job failed"
          raise "Battle simulation failed: #{message}"
        end

        return if statuses.all? { |status| status == "completed" }

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          raise "Timed out waiting for #{ids.size} battle job(s) (statuses=#{statuses.tally})"
        end

        sleep 0.05
      end
    end
  end
end
