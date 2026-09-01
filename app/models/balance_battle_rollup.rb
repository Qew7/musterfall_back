class BalanceBattleRollup < ApplicationRecord
  belongs_to :catalog_version
  belongs_to :round_matchup, optional: true
  belongs_to :game, optional: true
  belongs_to :balance_simulation_run, optional: true

  validates :matchup_type, :source, presence: true
end
