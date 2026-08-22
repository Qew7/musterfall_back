class PlayerAction < ApplicationRecord
  belongs_to :game, optional: true

  validates :action, :http_status, presence: true
end
