module Balance
  module DuelRuns
    module_function

    def run_deploy(run)
      config = run.config.is_a?(Hash) ? run.config : {}
      config["deploy"].presence || config[:deploy].presence || "melee"
    end

    def filtered(catalog_version_id: nil, contact: nil, deploy: nil)
      version = Balance::Dashboard.resolve_version(catalog_version_id)
      BalanceDuelRun.where(catalog_version_id: version.id).select do |run|
        (contact.blank? || run.contact == contact.to_s) &&
          (deploy.blank? || run_deploy(run) == deploy.to_s)
      end
    end

    def matchup_rows(runs)
      grouped = runs.group_by { |run| [ run.left_template, run.right_template, run.contact, run_deploy(run) ] }
      grouped.map do |(left, right, contact, deploy), entries|
        iterations = entries.sum(&:iterations)
        left_wins = entries.sum(&:left_wins)
        right_wins = entries.sum(&:right_wins)
        avg_rounds = iterations.positive? ? (entries.sum { |e| e.avg_rounds.to_f * e.iterations } / iterations).round(2) : 0.0

        {
          key: "#{left} vs #{right} (#{contact}/#{deploy})",
          left_template: left,
          right_template: right,
          contact: contact,
          deploy: deploy,
          runs: entries.length,
          iterations: iterations,
          left_wins: left_wins,
          right_wins: right_wins,
          left_winrate: rate(left_wins, left_wins + right_wins),
          avg_rounds: avg_rounds
        }
      end.sort_by { |row| -row[:iterations] }
    end

    def unit_winrate_rows(runs, units)
      stats = Hash.new { |hash, key| hash[key] = { wins: 0, total: 0 } }
      runs.each do |run|
        stats[run.left_template][:wins] += run.left_wins.to_i
        stats[run.left_template][:total] += run.iterations.to_i
        stats[run.right_template][:wins] += run.right_wins.to_i
        stats[run.right_template][:total] += run.iterations.to_i
      end

      units.values.map do |unit|
        bucket = stats[unit.template_key]
        {
          template_key: unit.template_key,
          faction_slug: unit.faction.slug,
          recruit_tier: unit.recruit_tier,
          cost: unit.cost,
          winrate: rate(bucket[:wins], bucket[:total]),
          wins: bucket[:wins],
          iterations: bucket[:total]
        }
      end
    end

    def rate(numerator, denominator)
      return 0.0 if denominator.to_i <= 0

      (numerator.to_f / denominator).round(4)
    end
  end
end
