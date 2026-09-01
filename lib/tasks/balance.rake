namespace :balance do
  desc "Print duel winrate report grouped by recruit_tier (CONTACT=front DEPLOY=melee|ranged)"
  task duel_tier_report: :environment do
    Balance::TierReport.print_report(contact: ENV["CONTACT"].presence, deploy: ENV["DEPLOY"].presence)
  end

  desc "Print cost vs winrate audit (CONTACT= DEPLOY=)"
  task cost_audit: :environment do
    Balance::CostAudit.print_report(contact: ENV["CONTACT"].presence, deploy: ENV["DEPLOY"].presence)
  end

  desc "Compare unit winrates between catalog versions (FROM=5 TO=6 CONTACT= DEPLOY=)"
  task compare_versions: :environment do
    from = ENV["FROM"].presence || abort("FROM required")
    to = ENV["TO"].presence || abort("TO required")
    Balance::CompareVersions.print_report(
      from_version_id: from,
      to_version_id: to,
      contact: ENV["CONTACT"].presence,
      deploy: ENV["DEPLOY"].presence
    )
  end

  desc "Backfill balance rollups from completed RoundMatchups"
  task backfill: :environment do
    processed = 0
    skipped = 0

    RoundMatchup.where(status: "completed").order(:id).find_each do |matchup|
      if BalanceBattleRollup.exists?(round_matchup_id: matchup.id)
        skipped += 1
        next
      end

      Balance::Record.from_matchup!(matchup)
      processed += 1
    end

    puts "balance backfill: processed=#{processed} skipped=#{skipped}"
  end
end
