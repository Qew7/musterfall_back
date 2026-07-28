class SimulateBattleJob < ApplicationJob
  queue_as :battles

  # Idempotent: completed matchups are skipped on retry.
  def perform(round_matchup_id)
    matchup = RoundMatchup.find(round_matchup_id)
    return if matchup.completed?

    matchup.update!(status: "running", error_message: nil)

    catalog = Sim::Catalog::Loader.load
    map_seed = Sim::Battle::TerrainMap.map_seed(rng_seed: matchup.game.rng_seed, round: matchup.campaign_round)
    result = Sim::Battle::Simulator.call(
      matchup.attacker_player,
      matchup.defender_player,
      catalog,
      rng: Sim::Rng::Seeded.new(matchup.seed),
      map_seed: map_seed
    )

    matchup.update!(
      status: "completed",
      result_payload: deep_stringify(result),
      error_message: nil
    )
  rescue StandardError => error
    matchup&.update!(status: "failed", error_message: error.message)
    raise
  end

  private

  def deep_stringify(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, entry), memo|
        memo[key.to_s] = deep_stringify(entry)
      end
    when Array
      value.map { |entry| deep_stringify(entry) }
    else
      value
    end
  end
end
