class BattleRound < ApplicationRecord
  belongs_to :battle

  has_many :battle_turns, -> { order(:position) }, dependent: :destroy

  validates :number, numericality: { greater_than_or_equal_to: 1 }
end
