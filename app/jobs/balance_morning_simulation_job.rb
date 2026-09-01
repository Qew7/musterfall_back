class BalanceMorningSimulationJob < ApplicationJob
  queue_as :balance

  ARMY_CONFIG = {
    preset: "balanced_random",
    battle_limit: 1000,
    target_points: 1000,
    budget_mode: "fixed",
    round: 3,
    hero_level: 2,
    randomize_hero_level: false
  }.freeze

  DUEL_MATRIX_CONFIG = {
    contact: "front",
    deploy: "ranged",
    random_first_turn: true,
    iterations: 50,
    batch_size: 10
  }.freeze

  def perform
    start_army_simulation
    start_duel_matrix
  end

  private

  def start_army_simulation
    run = Balance::Simulation.start!(config: ARMY_CONFIG)
    Rails.logger.info("[BalanceMorningSimulationJob] started army run ##{run.id}")
  rescue ArgumentError => error
    Rails.logger.warn("[BalanceMorningSimulationJob] army: #{error.message}")
  end

  def start_duel_matrix
    run = Balance::DuelMatrix.start!(config: DUEL_MATRIX_CONFIG)
    Rails.logger.info("[BalanceMorningSimulationJob] started duel matrix ##{run.id}")
  rescue ArgumentError => error
    Rails.logger.warn("[BalanceMorningSimulationJob] duel matrix: #{error.message}")
  end
end
