class GamePlayer < ApplicationRecord
  STATUSES = %w[active eliminated].freeze

  belongs_to :game
  has_many :game_entities, dependent: :destroy

  validates :external_key, :name, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :treasury, :victories, :position, numericality: { greater_than_or_equal_to: 0 }
  validates :external_key, uniqueness: { scope: :game_id }
end
