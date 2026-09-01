class BalanceDuelRun < ApplicationRecord
  belongs_to :catalog_version

  validates :left_template, :right_template, :contact, presence: true
  validates :iterations, numericality: { greater_than: 0 }
  validates :left_wins, :right_wins, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }
end
