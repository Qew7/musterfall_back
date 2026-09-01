module Balance
  module CompareVersions
    SIGNIFICANT_DELTA = 0.10

    module_function

    def build(from_version_id:, to_version_id:, contact: nil, deploy: nil)
      from_rows = version_rows(from_version_id, contact:, deploy:)
      to_rows = version_rows(to_version_id, contact:, deploy:)
      keys = (from_rows.keys | to_rows.keys).sort

      {
        from_version_id: from_version_id.to_i,
        to_version_id: to_version_id.to_i,
        contact_filter: contact,
        deploy_filter: deploy,
        templates: keys.filter_map { |key| diff_row(key, from_rows[key], to_rows[key]) }
      }
    end

    def print_report(from_version_id:, to_version_id:, contact: nil, deploy: nil)
      payload = build(from_version_id:, to_version_id:, contact:, deploy:)
      puts "Balance version diff #{payload[:from_version_id]} -> #{payload[:to_version_id]} (contact=#{payload[:contact_filter] || 'all'}, deploy=#{payload[:deploy_filter] || 'all'})"
      puts

      payload[:templates].each do |row|
        flag = row[:significant] ? " !" : ""
        puts format(
          "  %-18s %5.1f%% -> %5.1f%% (%+.1f%%)  iters %d->%d%s",
          row[:template_key],
          row[:from_winrate] * 100,
          row[:to_winrate] * 100,
          row[:delta] * 100,
          row[:from_iterations],
          row[:to_iterations],
          flag
        )
      end
    end

    def version_rows(catalog_version_id, contact:, deploy:)
      runs = Balance::DuelRuns.filtered(catalog_version_id:, contact:, deploy:)
      units = TierReport.unit_index
      Balance::DuelRuns.unit_winrate_rows(runs, units).index_by { |row| row[:template_key] }
    end

    def diff_row(template_key, from_row, to_row)
      from_winrate = from_row&.dig(:winrate) || 0.0
      to_winrate = to_row&.dig(:winrate) || 0.0
      from_iterations = from_row&.dig(:iterations).to_i
      to_iterations = to_row&.dig(:iterations).to_i
      delta = (to_winrate - from_winrate).round(4)

      {
        template_key: template_key,
        recruit_tier: (from_row || to_row)[:recruit_tier],
        from_winrate: from_winrate,
        to_winrate: to_winrate,
        delta: delta,
        from_iterations: from_iterations,
        to_iterations: to_iterations,
        significant: from_iterations >= TierReport::LOW_SAMPLE_ITERATIONS &&
          to_iterations >= TierReport::LOW_SAMPLE_ITERATIONS &&
          delta.abs >= SIGNIFICANT_DELTA
      }
    end
  end
end
