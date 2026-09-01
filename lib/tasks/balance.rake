namespace :balance do
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
