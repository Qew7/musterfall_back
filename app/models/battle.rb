class Battle < ApplicationRecord
  belongs_to :game

  has_many :battle_rounds, -> { order(:number) }, dependent: :destroy

  validates :round_number, numericality: { greater_than_or_equal_to: 1 }
  validates :left_player_id, :left_player_name, :right_player_id, :right_player_name, :winner_id, :winner_name, :summary, presence: true
end
