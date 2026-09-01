# frozen_string_literal: true

module Balance
  module BattleReport
    module_function

    def build(catalog_version_id: nil, matchup_type: "all", contact: nil, deploy: nil)
      version = Dashboard.resolve_version(catalog_version_id)
      scoped_type = Dashboard.normalize_matchup_type(matchup_type)
      counters = Dashboard.load_counters(version.id, scoped_type)
      battles = BalanceBattleRollup.where(catalog_version_id: version.id)
      battles = battles.where(matchup_type: scoped_type) unless scoped_type == "all"
      duel_runs = DuelRuns.filtered(catalog_version_id: version.id, contact: contact, deploy: deploy)
      units = TierReport.unit_index

      {
        catalog_version_id: version.id,
        matchup_type: scoped_type,
        contact_filter: contact,
        deploy_filter: deploy,
        battles: {
          summary: Dashboard.summary_payload(counters, battles.count),
          faction_wins: Dashboard.faction_wins(counters)
        },
        duels: duel_summary(duel_runs, units)
      }
    end

    def duel_summary(runs, units)
      iterations = runs.sum(&:iterations)
      avg_rounds =
        if iterations.positive?
          (runs.sum { |entry| entry.avg_rounds.to_f * entry.iterations } / iterations).round(2)
        else
          0.0
        end

      {
        summary: {
          duel_run_count: runs.length,
          total_iterations: iterations,
          avg_rounds: avg_rounds,
          matchup_count: DuelRuns.matchup_rows(runs).length
        }.merge(Upset.duel_counts(runs, units))
      }
    end

    def print_report(catalog_version_id: nil, matchup_type: "all", contact: nil, deploy: nil)
      payload = build(
        catalog_version_id: catalog_version_id,
        matchup_type: matchup_type,
        contact: contact,
        deploy: deploy
      )
      battles = payload[:battles]
      summary = battles[:summary]

      puts "Balance battle report (catalog_version_id=#{payload[:catalog_version_id]}, matchup_type=#{payload[:matchup_type]})"
      puts "battles=#{summary[:battle_count]} recorded=#{summary[:recorded_battles]} upsets=#{summary[:upset_count]} (#{format('%.1f%%', summary[:upset_rate] * 100)}) avg_rounds=#{summary[:avg_rounds]}"
      puts
      puts "FACTION WINS"
      battles[:faction_wins].each do |row|
        puts format("  %-14s %5d  %5.1f%%", row[:faction_id], row[:wins], row[:winrate] * 100)
      end
      puts

      duels = payload[:duels][:summary]
      puts "DUELS (contact=#{payload[:contact_filter] || 'all'}, deploy=#{payload[:deploy_filter] || 'all'})"
      puts "runs=#{duels[:duel_run_count]} iterations=#{duels[:total_iterations]} matchups=#{duels[:matchup_count]} upsets=#{duels[:upset_count]} (#{format('%.1f%%', duels[:upset_rate] * 100)}) avg_rounds=#{duels[:avg_rounds]}"
    end
  end
end
