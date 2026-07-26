class GameEntity < ApplicationRecord
  KINDS = %w[unit hero].freeze
  ROWS = %w[front support rear reserve].freeze
  LANES = %w[left center right].freeze

  belongs_to :game_player
  has_one :hero_attachment, class_name: "GameEntityAttachment", foreign_key: :hero_entity_id, dependent: :destroy, inverse_of: :hero_entity
  has_many :unit_attachments, class_name: "GameEntityAttachment", foreign_key: :unit_entity_id, dependent: :destroy, inverse_of: :unit_entity

  validates :external_key, :kind, :template_key, :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :row_key, inclusion: { in: ROWS }
  validates :lane_key, inclusion: { in: LANES }
  validates :external_key, uniqueness: { scope: :game_player_id }
  validates :current_health, numericality: { greater_than_or_equal_to: 0 }
end
