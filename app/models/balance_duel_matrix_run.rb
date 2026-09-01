class BalanceDuelMatrixRun < ApplicationRecord
  STATUSES = %w[pending running stopping stopped completed failed].freeze

  belongs_to :catalog_version

  validates :status, inclusion: { in: STATUSES }
  validates :seed, presence: true

  scope :active, -> { where(status: %w[pending running stopping]) }
  scope :recent, -> { order(created_at: :desc) }

  def running?
    status == "running"
  end

  def stopping?
    status == "stopping"
  end

  def stop!
    update!(status: "stopping") if status == "running"
  end
end
