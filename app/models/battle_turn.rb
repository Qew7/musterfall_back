class BattleTurn < ApplicationRecord
  belongs_to :battle_round

  has_many :battle_phases, -> { order(:position) }, dependent: :destroy

  validates :position, numericality: { greater_than_or_equal_to: 0 }
  validates :player_id, :player_name, presence: true
end
