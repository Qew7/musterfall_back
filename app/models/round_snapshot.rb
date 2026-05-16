class RoundSnapshot < ApplicationRecord
  PHASES = %w[pre_round post_round].freeze

  belongs_to :game

  validates :round_number, numericality: { greater_than_or_equal_to: 1 }
  validates :phase, inclusion: { in: PHASES }
  validates :phase, uniqueness: { scope: [:game_id, :round_number] }
end