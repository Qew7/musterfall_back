class HeroUpgrade < ApplicationRecord
  validates :upgrade_key, :name, :category, :summary, presence: true
  validates :upgrade_key, uniqueness: true
end
