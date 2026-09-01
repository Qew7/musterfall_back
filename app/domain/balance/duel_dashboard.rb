module Balance
  module DuelDashboard
    module_function

    def build(catalog_version_id: nil, contact: nil, deploy: nil)
      version = Balance::Dashboard.resolve_version(catalog_version_id)
      runs = Balance::DuelRuns.filtered(catalog_version_id: version.id, contact: contact, deploy: deploy)

      {
        catalog_versions: catalog_versions_payload,
        selected_version_id: version.id,
        contact_filter: contact,
        deploy_filter: deploy,
        summary: summary_payload(runs),
        template_wins: template_wins(runs),
        matchups: Balance::DuelRuns.matchup_rows(runs),
        recent_runs: recent_runs(runs),
        active_duel_matrix: active_duel_matrix_payload,
        duel_matrix_runs: duel_matrix_runs_payload
      }
    end

    def active_duel_matrix_payload
      run = BalanceDuelMatrixRun.active.order(created_at: :desc).first
      return nil unless run

      Balance::DuelMatrix.serialize_run(run)
    end

    def duel_matrix_runs_payload
      BalanceDuelMatrixRun.recent.limit(5).map { |run| Balance::DuelMatrix.serialize_run(run) }
    end

    def summary_payload(runs)
      entries = runs.to_a
      iterations = entries.sum(&:iterations)
      avg_rounds =
        if iterations.positive?
          (entries.sum { |entry| entry.avg_rounds.to_f * entry.iterations } / iterations).round(2)
        else
          0.0
        end

      {
        duel_run_count: entries.length,
        total_iterations: iterations,
        avg_rounds: avg_rounds
      }
    end

    def template_wins(runs)
      totals = Hash.new(0)
      runs.each do |run|
        totals[run.left_template] += run.left_wins.to_i
        totals[run.right_template] += run.right_wins.to_i
      end
      total = totals.values.sum
      totals.sort_by { |_, wins| -wins }.map do |template_id, wins|
        {
          template_id: template_id,
          wins: wins,
          winrate: rate(wins, total)
        }
      end
    end

    def recent_runs(runs)
      runs.sort_by(&:created_at).reverse.first(20).map do |run|
        {
          id: run.id,
          created_at: run.created_at,
          left_template: run.left_template,
          right_template: run.right_template,
          contact: run.contact,
          deploy: Balance::DuelRuns.run_deploy(run),
          iterations: run.iterations,
          left_wins: run.left_wins,
          right_wins: run.right_wins,
          left_winrate: run.left_winrate.to_f,
          avg_rounds: run.avg_rounds.to_f,
          left_models: run.left_models,
          right_models: run.right_models
        }
      end
    end

    def catalog_versions_payload
      duel_counts = BalanceDuelRun.group(:catalog_version_id).count
      battle_counts = BalanceBattleRollup.group(:catalog_version_id).count
      CatalogVersion.order(id: :desc).map do |version|
        {
          id: version.id,
          content_hash: version.content_hash,
          catalog_hash: version.catalog_hash,
          rules_hash: version.rules_hash,
          created_at: version.created_at,
          battle_count: battle_counts[version.id].to_i,
          duel_count: duel_counts[version.id].to_i
        }
      end
    end

    def rate(numerator, denominator)
      return 0.0 if denominator.to_i <= 0

      (numerator.to_f / denominator).round(4)
    end
  end
end
