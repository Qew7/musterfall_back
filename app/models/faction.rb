class Faction < ApplicationRecord
  has_many :army_templates, -> { order(:kind, :created_at) }, dependent: :destroy
  has_many :units, -> { where(kind: "unit").order(:name) }, class_name: "ArmyTemplate", dependent: :destroy
  has_many :heroes, -> { where(kind: "hero").order(:id) }, class_name: "ArmyTemplate", dependent: :destroy

  validates :slug, :name, :vibe, :passive, :color, presence: true
  validates :slug, uniqueness: true
end
