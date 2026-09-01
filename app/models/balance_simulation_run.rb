class BalanceSimulationRun < ApplicationRecord
  STATUSES = %w[pending running stopping stopped completed failed].freeze

  belongs_to :catalog_version
  has_many :balance_battle_rollups, dependent: :nullify

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

  def battle_limit
    value = config["battle_limit"] || config[:battle_limit]
    return nil if value.blank?

    value.to_i
  end

  def limit_reached?
    limit = battle_limit
    return false unless limit

    battles_completed >= limit
  end
end
