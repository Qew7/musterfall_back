namespace :balance do
  desc "Print duel winrate report grouped by recruit_tier (CONTACT=front DEPLOY=melee|ranged)"
  task duel_tier_report: :environment do
    Balance::TierReport.print_report(contact: ENV["CONTACT"].presence, deploy: ENV["DEPLOY"].presence)
  end

  desc "Print cost vs winrate audit (CONTACT= DEPLOY=)"
  task cost_audit: :environment do
    Balance::CostAudit.print_report(contact: ENV["CONTACT"].presence, deploy: ENV["DEPLOY"].presence)
  end

  desc "Print battle summary: faction wins, upset, duel upset (MATCHUP_TYPE=all CONTACT= DEPLOY=)"
  task battle_report: :environment do
    Balance::BattleReport.print_report(
      catalog_version_id: ENV["CATALOG_VERSION_ID"].presence,
      matchup_type: ENV["MATCHUP_TYPE"].presence || "all",
      contact: ENV["CONTACT"].presence,
      deploy: ENV["DEPLOY"].presence
    )
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

  desc "Print battle rule concept index from # rule: headers (KEYS=shieldwall,fear)"
  task rule_index: :environment do
    keys = ENV["KEYS"]&.split(",")&.map(&:strip)&.presence
    Balance::RuleCatalog.print_index(keys: keys)
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
