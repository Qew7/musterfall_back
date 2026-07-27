class Game < ApplicationRecord
  STATUSES = %w[draft active finished].freeze

  has_many :battles, -> { order(:round_number, :id) }, dependent: :destroy
  has_many :round_snapshots, -> { order(:round_number, :phase) }, dependent: :destroy
  has_many :game_players, -> { order(:position) }, dependent: :destroy
  has_many :round_matchups, -> { order(:campaign_round, :position) }, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :player_count, numericality: { greater_than_or_equal_to: 2 }
  validates :current_round, numericality: { greater_than_or_equal_to: 1 }
  validates :campaign_version, numericality: { greater_than_or_equal_to: 0 }
end
