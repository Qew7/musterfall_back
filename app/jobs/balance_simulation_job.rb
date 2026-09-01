class BalanceSimulationJob < ApplicationJob
  queue_as :balance

  def perform(run_id)
    run = BalanceSimulationRun.find(run_id)
    return unless run.running? || run.status == "pending" || run.stopping?

    run.update!(status: "running", started_at: run.started_at || Time.current, error_message: nil)
    catalog = Sim::Catalog::Loader.load
    rng = Sim::Rng::Seeded.new(run.seed)

    loop do
      run.reload
      break if run.stopping? || run.status == "stopped"
      break if run.limit_reached?

      begin
        Synthetic::Play.call!(run: run, catalog: catalog, rng: rng)
        run.increment!(:battles_completed)
      rescue StandardError => error
        run.increment!(:battles_failed)
        run.update!(error_message: error.message)
        break if run.battles_failed >= 5
      end
    end

    final_status =
      if run.status == "failed"
        "failed"
      elsif run.stopping?
        "stopped"
      else
        "completed"
      end
    run.update!(status: final_status, finished_at: Time.current) unless run.status.in?(%w[stopped failed])
  end
end
