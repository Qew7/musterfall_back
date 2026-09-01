class BalanceSimulationJob < ApplicationJob
  queue_as :balance

  def perform(run_id)
    Balance::Simulation::BattleRunner.run_sync!(run_id)
  end
end
