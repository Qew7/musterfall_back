module Balance
  module Persist
    module_function

    def call!(result:, attacker:, defender:, catalog_version:, round_matchup_id: nil, game_id: nil, source: "campaign",
      balance_simulation_run_id: nil, metrics_extra: {})
      return if round_matchup_id && BalanceBattleRollup.exists?(round_matchup_id: round_matchup_id)

      payload = Rollup.build(
        result: result,
        attacker: attacker,
        defender: defender,
        catalog_version_id: catalog_version.id,
        round_matchup_id: round_matchup_id,
        game_id: game_id,
        source: source
      )
      payload[:metrics].merge!(metrics_extra) if metrics_extra.present?

      ActiveRecord::Base.transaction do
        BalanceBattleRollup.create!(
          catalog_version: catalog_version,
          round_matchup_id: round_matchup_id,
          game_id: game_id,
          balance_simulation_run_id: balance_simulation_run_id,
          matchup_type: payload[:metrics][:matchup_type],
          source: source,
          metrics: payload[:metrics]
        )
        upsert_counters!(catalog_version.id, payload[:counters])
      end
    end

    def upsert_counters!(catalog_version_id, rows)
      return if rows.empty?

      timestamp = Time.current
      values = rows.map { |row|
        {
          catalog_version_id: catalog_version_id,
          bucket: row[:bucket],
          key: row[:key],
          matchup_type: row[:matchup_type],
          n: row[:n],
          sum: row[:sum],
          created_at: timestamp,
          updated_at: timestamp
        }
      }

      BalanceCounter.upsert_all(
        values,
        unique_by: :index_balance_counters_unique,
        on_duplicate: Arel.sql("n = balance_counters.n + EXCLUDED.n, sum = balance_counters.sum + EXCLUDED.sum, updated_at = EXCLUDED.updated_at")
      )
    end
  end
end
