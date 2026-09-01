module Balance
  module CostAudit
    RECRUIT_TIERS = ArmyTemplate::RECRUIT_TIERS
    COST_RATIO_HIGH = 1.25
    COST_RATIO_LOW = 0.85

    module_function

    def build(catalog_version_id: nil, contact: nil, deploy: nil)
      runs = Balance::DuelRuns.filtered(catalog_version_id: catalog_version_id, contact: contact, deploy: deploy)
      units = TierReport.unit_index
      rows = Balance::DuelRuns.unit_winrate_rows(runs, units)

      {
        catalog_version_id: Balance::Dashboard.resolve_version(catalog_version_id).id,
        contact_filter: contact,
        deploy_filter: deploy,
        by_tier: RECRUIT_TIERS.index_with { |tier| tier_section(tier, rows) }
      }
    end

    def print_report(catalog_version_id: nil, contact: nil, deploy: nil)
      payload = build(catalog_version_id: catalog_version_id, contact: contact, deploy: deploy)
      puts "Balance cost audit (catalog_version_id=#{payload[:catalog_version_id]}, contact=#{payload[:contact_filter] || 'all'}, deploy=#{payload[:deploy_filter] || 'all'})"
      puts

      payload[:by_tier].each do |tier, section|
        puts "== #{tier.upcase} (median cost=#{section[:median_cost]}) =="
        section[:rows].each do |row|
          puts format(
            "  %-18s cost=%-4s ratio=%.2f win=%5.1f%%  %-20s %s",
            row[:template_key], row[:cost], row[:cost_ratio], row[:winrate] * 100, row[:verdict], row[:faction_slug]
          )
        end
        puts
      end
    end

    def tier_section(tier, rows)
      tier_rows = rows.select { |row| row[:recruit_tier] == tier }
      median = median_cost(tier_rows)
      tier_avg_winrate = average_winrate(tier_rows)

      {
        median_cost: median,
        tier_avg_winrate: tier_avg_winrate,
        rows: tier_rows
          .map { |row| enrich_row(row, tier:, median:, tier_avg_winrate:) }
          .sort_by { |row| -row[:cost_ratio].abs + -row[:winrate_delta].abs }
      }
    end

    def enrich_row(row, tier:, median:, tier_avg_winrate:)
      cost_ratio = median.positive? ? (row[:cost].to_f / median).round(3) : 1.0
      win_target = tier == "line" ? TierReport::LINE_TARGET : tier_avg_winrate
      winrate_delta = (row[:winrate] - win_target).round(4)

      row.merge(
        tier_median_cost: median,
        cost_ratio: cost_ratio,
        winrate_delta: winrate_delta,
        verdict: verdict(tier, row, cost_ratio, winrate_delta)
      )
    end

    def verdict(_tier, row, cost_ratio, winrate_delta)
      return "low_sample" if row[:iterations].to_i < TierReport::LOW_SAMPLE_ITERATIONS
      return "overcosted_weak" if cost_ratio >= COST_RATIO_HIGH && winrate_delta <= -0.10
      return "undercosted_strong" if cost_ratio <= COST_RATIO_LOW && winrate_delta >= 0.10
      return "overcosted_but_wins" if cost_ratio >= COST_RATIO_HIGH && winrate_delta >= 0.05
      return "cheap_but_loses" if cost_ratio <= COST_RATIO_LOW && winrate_delta <= -0.05
      return "underperformer" if winrate_delta <= -0.15
      return "overperformer" if winrate_delta >= 0.15

      "fair"
    end

    def median_cost(rows)
      costs = rows.map { |row| row[:cost] }.sort
      return 0 if costs.empty?

      mid = costs.length / 2
      costs.length.odd? ? costs[mid] : (costs[mid - 1] + costs[mid]) / 2.0
    end

    def average_winrate(rows)
      sampled = rows.select { |row| row[:iterations].to_i.positive? }
      return TierReport::LINE_TARGET if sampled.empty?

      (sampled.sum { |row| row[:winrate] } / sampled.length).round(4)
    end
  end
end
