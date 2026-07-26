class GameEntityAttachment < ApplicationRecord
  SLOTS = %w[front left right rear].freeze

  belongs_to :hero_entity, class_name: "GameEntity", inverse_of: :hero_attachment
  belongs_to :unit_entity, class_name: "GameEntity", inverse_of: :unit_attachments

  validates :slot, inclusion: { in: SLOTS }
  validates :hero_entity_id, uniqueness: true
  validates :slot, uniqueness: { scope: :unit_entity_id }
end
