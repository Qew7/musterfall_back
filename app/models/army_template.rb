class ArmyTemplate < ApplicationRecord
    validates :attacks, numericality: { greater_than: 0 }
  # Количество атак по умолчанию 1, у героев/монстров может быть больше
  KINDS = %w[unit hero].freeze
  ATTACK_TEMPLATES = %w[single volley blast breath].freeze
  MAX_FORMATION_FILES = 5
  MODEL_CLASSES = {
    "infantry" => { width: 1, depth: 1 },
    "cavalry" => { width: 1, depth: 2 },
    "monster" => { width: 2, depth: 2 },
    "machine" => { width: 2, depth: 2 }
  }.freeze

  belongs_to :faction
  has_many :army_template_abilities, dependent: :destroy
  has_many :abilities_records, through: :army_template_abilities, source: :ability

  validates :template_key, :kind, :name, :armor_type, :weapon_type, presence: true
  validates :template_key, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :model_class, inclusion: { in: MODEL_CLASSES.keys }
  validates :cost, :models, :model_health, :width, :base_depth, :initiative, :movement, :morale, :skill, numericality: { greater_than: 0 }
  validates :width, numericality: { less_than_or_equal_to: MAX_FORMATION_FILES }
  validates :skill, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 6 }
  validates :model_base_width, :model_base_depth, numericality: { greater_than: 0 }, allow_nil: true
  validates :shooting_range, :spell_range, numericality: { greater_than_or_equal_to: 0 }
  validates :melee, :ranged, :spell, numericality: { greater_than_or_equal_to: 0 }
  validates :shooting_template, :spell_template, inclusion: { in: ATTACK_TEMPLATES }

  def abilities_list
    abilities_records.order(:key).pluck(:key)
  end

  def effective_model_base_width
    model_base_width || MODEL_CLASSES.fetch(model_class).fetch(:width)
  end

  def effective_model_base_depth
    model_base_depth || MODEL_CLASSES.fetch(model_class).fetch(:depth)
  end
end
