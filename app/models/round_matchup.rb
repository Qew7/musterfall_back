class RoundMatchup < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  belongs_to :game

  validates :status, inclusion: { in: STATUSES }
  validates :campaign_round, :position, :seed, presence: true
  validates :attacker_player_key, :defender_player_key, presence: true
  validates :position, uniqueness: { scope: [ :game_id, :campaign_round ] }

  scope :for_round, ->(game, round) { where(game_id: game.id, campaign_round: round) }

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def attacker_player
    deep_symbolize(attacker_snapshot)
  end

  def defender_player
    deep_symbolize(defender_snapshot)
  end

  def battle_result
    deep_symbolize(result_payload)
  end

  private

  def deep_symbolize(value)
    Sim::Campaign::State.deep_symbolize(value)
  end
end
