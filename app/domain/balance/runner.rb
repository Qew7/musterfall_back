module Balance
  module Runner
    module_function

    def enqueue_simulation!(run_id, count: Balance::Simulation.worker_count)
      if count <= 1
        enqueue_sync!(run_id)
      else
        enqueue_workers!(run_id, count: count)
      end
    end

    def enqueue_sync!(run_id)
      if background_jobs?
        BalanceSimulationJob.perform_later(run_id)
      else
        Thread.new do
          Rails.application.executor.wrap do
            BalanceSimulationJob.perform_now(run_id)
          end
        end
      end
    end

    def enqueue_workers!(run_id, count: Balance::Simulation.worker_count)
      count.times { enqueue_worker!(run_id) }
    end

    def enqueue_worker!(run_id)
      if background_jobs?
        BalanceSimulationWorkerJob.perform_later(run_id)
      else
        Thread.new do
          Rails.application.executor.wrap do
            BalanceSimulationWorkerJob.perform_now(run_id)
          end
        end
      end
    end

    def enqueue_backfill!
      if background_jobs?
        BalanceBackfillJob.perform_later
      else
        Thread.new do
          Rails.application.executor.wrap do
            BalanceBackfillJob.perform_now
          end
        end
      end
    end

    def enqueue_duel_matrix_batch!(matrix_run_id, batch_index, anchors, all_templates)
      if background_jobs?
        BalanceDuelMatrixBatchJob.perform_later(matrix_run_id, batch_index, anchors, all_templates)
      else
        Thread.new do
          Rails.application.executor.wrap do
            BalanceDuelMatrixBatchJob.perform_now(matrix_run_id, batch_index, anchors, all_templates)
          end
        end
      end
    end

    def enqueue_duel_matrix_finalize!(matrix_run_id)
      if background_jobs?
        BalanceDuelMatrixFinalizeJob.perform_later(matrix_run_id)
      else
        Thread.new do
          Rails.application.executor.wrap do
            BalanceDuelMatrixFinalizeJob.perform_now(matrix_run_id)
          end
        end
      end
    end

    def background_jobs?
      ENV["SOLID_QUEUE_IN_PUMA"].present? ||
        ENV["SOLID_QUEUE_EXTERNAL"].present? ||
        !Rails.env.development?
    end
  end
end
