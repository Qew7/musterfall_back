class BalanceCounter < ApplicationRecord
  belongs_to :catalog_version

  validates :bucket, :key, :matchup_type, presence: true
end
