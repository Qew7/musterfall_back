class BalanceDuelMatrixFinalizeJob < ApplicationJob
  queue_as :balance

  def perform(matrix_run_id)
    run = BalanceDuelMatrixRun.find(matrix_run_id)
    return unless run.stopping?

    run.update!(status: "stopped", finished_at: Time.current)
  end
end
