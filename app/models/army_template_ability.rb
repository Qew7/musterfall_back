class ArmyTemplateAbility < ApplicationRecord
  belongs_to :army_template
  belongs_to :ability

  validates :ability_id, uniqueness: { scope: :army_template_id }
end