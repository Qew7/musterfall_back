module Balance
  module TierReport
    RECRUIT_TIERS = ArmyTemplate::RECRUIT_TIERS
    LINE_TARGET = 0.5
    LINE_TOLERANCE = 0.15
    RARE_SKEW = 0.40
    CROSS_TIER_LEAK = 0.85
    LOW_SAMPLE_ITERATIONS = 30

    module_function

    def build(catalog_version_id: nil, contact: nil, deploy: nil)
      runs = Balance::DuelRuns.filtered(catalog_version_id: catalog_version_id, contact: contact, deploy: deploy)
      units = unit_index
      matchups = Balance::DuelRuns.matchup_rows(runs)

      {
        catalog_version_id: Balance::Dashboard.resolve_version(catalog_version_id).id,
        contact_filter: contact,
        deploy_filter: deploy,
        summary: summary_payload(runs, matchups),
        cost_outliers: cost_outlier_rows(catalog_version_id: catalog_version_id, contact: contact, deploy: deploy),
        by_tier: RECRUIT_TIERS.index_with { |tier| tier_section(tier, matchups, units) },
        cross_tier_leaks: cross_tier_leaks(matchups, units),
        low_sample_pairs: low_sample_pairs(matchups)
      }
    end

    def print_report(catalog_version_id: nil, contact: nil, deploy: nil)
      payload = build(catalog_version_id: catalog_version_id, contact: contact, deploy: deploy)
      puts "Balance tier report (catalog_version_id=#{payload[:catalog_version_id]}, contact=#{payload[:contact_filter] || 'all'}, deploy=#{payload[:deploy_filter] || 'all'})"
      puts "duel_runs=#{payload[:summary][:duel_run_count]} iterations=#{payload[:summary][:total_iterations]} matchups=#{payload[:summary][:matchup_count]}"
      puts

      if payload[:low_sample_pairs].any?
        puts "LOW SAMPLE (< #{LOW_SAMPLE_ITERATIONS} iterations): #{payload[:low_sample_pairs].length} pairs — rerun matrix before tuning"
        puts
      end

      payload[:cost_outliers].each do |row|
        puts "COST OUTLIER #{row[:template_key]} tier=#{row[:recruit_tier]} cost=#{row[:cost]} median=#{row[:tier_median_cost]} (#{row[:verdict]})"
      end
      puts if payload[:cost_outliers].any?

      payload[:by_tier].each do |tier, section|
        puts "== #{tier.upcase} vs #{tier.upcase} (#{section[:pair_count]} pairs) =="
        section[:unit_winrates].each do |row|
          puts format("  %-18s %5.1f%%  cost=%-4s  %s", row[:template_key], row[:winrate] * 100, row[:cost], row[:faction_slug])
        end
        section[:worst_pairs].each do |row|
          puts format(
            "  ! %-16s vs %-16s  %5.1f%% left  iters=%d",
            row[:left_template], row[:right_template], row[:left_winrate] * 100, row[:iterations]
          )
        end
        puts
      end

      payload[:cross_tier_leaks].each do |row|
        puts "CROSS-TIER #{row[:left_template]}(#{row[:left_tier]}) vs #{row[:right_template]}(#{row[:right_tier]}): #{format('%.1f%%', row[:left_winrate] * 100)} left"
      end
    end

    def unit_index
      ArmyTemplate.where(kind: "unit").includes(:faction).index_by(&:template_key)
    end

    def summary_payload(runs, matchups)
      iterations = runs.sum(&:iterations)
      avg_rounds =
        if iterations.positive?
          (runs.sum { |entry| entry.avg_rounds.to_f * entry.iterations } / iterations).round(2)
        else
          0.0
        end

      {
        duel_run_count: runs.length,
        total_iterations: iterations,
        avg_rounds: avg_rounds,
        matchup_count: matchups.length
      }
    end

    def tier_section(tier, matchups, units)
      pairs = same_tier_pairs(tier, matchups, units)
      {
        pair_count: pairs.length,
        unit_winrates: unit_winrates(tier, pairs, units),
        worst_pairs: worst_pairs(tier, pairs)
      }
    end

    def same_tier_pairs(tier, matchups, units)
      matchups.select do |row|
        left_tier = units[row[:left_template]]&.recruit_tier
        right_tier = units[row[:right_template]]&.recruit_tier
        left_tier == tier && right_tier == tier
      end
    end

    def unit_winrates(tier, pairs, units)
      stats = Hash.new { |hash, key| hash[key] = { wins: 0, total: 0 } }
      pairs.each do |row|
        stats[row[:left_template]][:wins] += row[:left_wins].to_i
        stats[row[:left_template]][:total] += row[:iterations].to_i
        stats[row[:right_template]][:wins] += row[:right_wins].to_i
        stats[row[:right_template]][:total] += row[:iterations].to_i
      end

      units.values
        .select { |unit| unit.recruit_tier == tier }
        .map do |unit|
          bucket = stats[unit.template_key]
          {
            template_key: unit.template_key,
            faction_slug: unit.faction.slug,
            cost: unit.cost,
            winrate: rate(bucket[:wins], bucket[:total]),
            wins: bucket[:wins],
            iterations: bucket[:total]
          }
        end
        .sort_by { |row| row[:winrate] }
    end

    def worst_pairs(tier, pairs)
      tolerance = tier == "line" ? LINE_TOLERANCE : tier == "rare" ? RARE_SKEW : 0.35
      pairs
        .map do |row|
          row.merge(deviation: (row[:left_winrate].to_f - LINE_TARGET).abs)
        end
        .select { |row| row[:deviation] >= tolerance }
        .sort_by { |row| -row[:deviation] }
        .first(12)
        .map do |row|
          row.slice(:left_template, :right_template, :left_winrate, :iterations, :deviation)
        end
    end

    def cross_tier_leaks(matchups, units)
      matchups.filter_map do |row|
        left = units[row[:left_template]]
        right = units[row[:right_template]]
        next unless left && right
        next if left.recruit_tier == right.recruit_tier

        winrate = row[:left_winrate].to_f
        next unless winrate >= CROSS_TIER_LEAK || winrate <= (1.0 - CROSS_TIER_LEAK)

        {
          left_template: row[:left_template],
          right_template: row[:right_template],
          left_tier: left.recruit_tier,
          right_tier: right.recruit_tier,
          left_winrate: winrate,
          iterations: row[:iterations],
          deviation: (winrate - LINE_TARGET).abs
        }
      end.sort_by { |row| -row[:deviation] }
    end

    def low_sample_pairs(matchups)
      matchups
        .select { |row| row[:iterations].to_i < LOW_SAMPLE_ITERATIONS }
        .map { |row| row.slice(:left_template, :right_template, :contact, :deploy, :iterations, :left_winrate) }
    end

    def cost_outlier_rows(catalog_version_id:, contact:, deploy:)
      CostAudit.build(catalog_version_id: catalog_version_id, contact: contact, deploy: deploy)[:by_tier]
        .flat_map { |_, section| section[:rows].select { |row| row[:cost_ratio] >= CostAudit::COST_RATIO_HIGH || row[:cost_ratio] <= CostAudit::COST_RATIO_LOW } }
    end

    def rate(numerator, denominator)
      Balance::DuelRuns.rate(numerator, denominator)
    end
  end
end
