class BalanceDuelMatrixBatchJob < ApplicationJob
  queue_as :balance

  def perform(matrix_run_id, batch_index, anchors, all_templates)
    run = BalanceDuelMatrixRun.find(matrix_run_id)
    return if run.status.in?(%w[stopped failed stopping])

    catalog = Sim::Catalog::Loader.load
    rng = Sim::Rng::Seeded.new(run.seed + batch_index.to_i)
    version = run.catalog_version
    base = run.config.deep_symbolize_keys

    Balance::DuelMatrix.pairs_for_batch(all_templates, anchors).each do |left, right|
      run.reload
      break if run.stopping? || run.status == "stopped" || run.status == "failed"

      duel_config = {
        left_template: left,
        right_template: right,
        contact: base[:contact],
        deploy: base[:deploy],
        random_first_turn: base[:random_first_turn],
        iterations: base[:iterations]
      }

      begin
        result = Balance::Synthetic::Duel.run!(catalog: catalog, config: duel_config, rng: rng)
        Balance::Duel::Persist.call!(result: result, config: duel_config, catalog_version: version)
        run.increment!(:matchups_completed)
      rescue StandardError => error
        run.increment!(:matchups_failed)
        run.update!(error_message: error.message, status: "failed", finished_at: Time.current)
        break
      end
    end
  ensure
    finalize_batch!(run) if run
  end

  private

  def finalize_batch!(run)
    return unless run

    run.with_lock do
      run.reload
      run.increment!(:batches_completed)
      return unless run.batches_completed >= run.batches_total
      return if run.status.in?(%w[failed stopped])

      final_status = run.stopping? ? "stopped" : "completed"
      run.update!(status: final_status, finished_at: Time.current)
    end
  end
end
