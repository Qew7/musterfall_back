class ArmyTemplate < ApplicationRecord
  KINDS = %w[unit hero].freeze
  ATTACK_TEMPLATES = %w[single volley blast breath].freeze

  belongs_to :faction
  has_many :army_template_abilities, dependent: :destroy
  has_many :abilities_records, through: :army_template_abilities, source: :ability

  validates :template_key, :kind, :name, :armor_type, :weapon_type, presence: true
  validates :template_key, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :cost, :models, :model_health, :width, :base_depth, :initiative, :movement, numericality: { greater_than: 0 }
  validates :shooting_range, :spell_range, numericality: { greater_than_or_equal_to: 0 }
  validates :melee, :ranged, :spell, numericality: { greater_than_or_equal_to: 0 }
  validates :shooting_template, :spell_template, inclusion: { in: ATTACK_TEMPLATES }

  def abilities_list
    abilities_records.order(:key).pluck(:key)
  end
end