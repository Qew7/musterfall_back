module Sim
  class Catalog
    attr_reader :formation_rules, :model_classes, :factions, :units, :heroes, :templates, :abilities, :hero_upgrades

    def initialize(formation_rules:, model_classes:, factions:, units:, heroes:, abilities:, hero_upgrades:)
      @formation_rules = formation_rules
      @model_classes = model_classes
      @factions = factions
      @units = units
      @heroes = heroes
      @templates = units + heroes
      @abilities = abilities
      @hero_upgrades = hero_upgrades
      @factions_by_id = factions.index_by { |entry| entry[:id] }
      @templates_by_id = @templates.index_by { |entry| entry[:id] }
      @abilities_by_id = abilities.index_by { |entry| entry[:id] }
      @hero_upgrades_by_id = hero_upgrades.index_by { |entry| entry[:id] }
      freeze
    end

    def faction(faction_id)
      @factions_by_id[faction_id]
    end

    def template(template_id)
      @templates_by_id[template_id]
    end

    def ability(ability_id)
      @abilities_by_id[ability_id]
    end

    def hero_upgrade(upgrade_id)
      @hero_upgrades_by_id[upgrade_id]
    end

    def unit_templates(faction_id)
      faction = faction(faction_id)
      return [] unless faction

      faction[:unit_pool].filter_map { |template_id| template(template_id) }
    end

    def hero_templates(faction_id)
      faction = faction(faction_id)
      return [] unless faction

      faction[:hero_pool].filter_map { |template_id| template(template_id) }
    end
  end
end
