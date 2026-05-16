class BattlePhase < ApplicationRecord
  TYPES = %w[start movement magic shooting melee].freeze

  belongs_to :battle_turn

  validates :position, numericality: { greater_than_or_equal_to: 0 }
  validates :phase_type, inclusion: { in: TYPES }
  validates :label, presence: true

  attribute :actions, :json, default: []
end
