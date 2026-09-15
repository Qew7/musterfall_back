class PurgeOldBattlesJob < ApplicationJob
  def perform
    Battle.where(created_at: ..3.weeks.ago).in_batches(&:destroy_all)
  end
end
