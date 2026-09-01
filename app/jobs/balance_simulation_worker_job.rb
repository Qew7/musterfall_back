class BalanceSimulationWorkerJob < ApplicationJob
  queue_as :balance

  def perform(run_id)
    Balance::Simulation::BattleRunner.run_worker!(run_id)
  end
end
