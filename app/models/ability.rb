class Ability < ApplicationRecord
  has_many :army_template_abilities, dependent: :destroy
  has_many :army_templates, through: :army_template_abilities

  validates :key, :name, :category, :description, presence: true
  validates :key, uniqueness: true
end
