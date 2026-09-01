class BalanceBackfillJob < ApplicationJob
  queue_as :balance

  def perform
    version = CatalogVersion.current!
    processed = 0
    skipped = 0

    RoundMatchup.where(status: "completed").order(:id).find_each do |matchup|
      if BalanceBattleRollup.exists?(round_matchup_id: matchup.id)
        skipped += 1
        next
      end

      Balance::Record.from_matchup!(matchup, catalog_version: version)
      processed += 1
    end

    Rails.logger.info("[BalanceBackfillJob] processed=#{processed} skipped=#{skipped}")
  end
end
