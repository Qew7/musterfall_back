class HeroUpgrade < ApplicationRecord
  belongs_to :faction, optional: true

  validates :upgrade_key, :name, :category, :summary, presence: true
  validates :upgrade_key, uniqueness: true
  validates :min_level, numericality: { greater_than: 0 }
end
