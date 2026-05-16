module Api
  class GameCatalogController < ApplicationController
    def show
      render json: {
        factions: Faction.order(:position).map { |faction| serialize_faction(faction) },
        units: Unit.includes(:faction, :abilities_records).order(:name).map { |template| serialize_template(template) },
        heroes: Hero.includes(:faction, :abilities_records).order(:name).map { |template| serialize_template(template) },
        abilities: Ability.order(:key).map { |ability| serialize_ability(ability) },
        hero_upgrades: HeroUpgrade.order(:position).map { |upgrade| serialize_upgrade(upgrade) }
      }
    end

    private

    def serialize_faction(faction)
      {
        id: faction.slug,
        name: faction.name,
        vibe: faction.vibe,
        passive: faction.passive,
        color: faction.color,
        unitPool: faction.units.map(&:template_key),
        heroPool: faction.heroes.map(&:template_key)
      }
    end

    def serialize_template(template)
      {
        id: template.template_key,
        kind: template.kind,
        factionId: template.faction.slug,
        name: template.name,
        cost: template.cost,
        models: template.models,
        modelHealth: template.model_health,
        width: template.width,
        baseDepth: template.base_depth,
        armorType: template.armor_type,
        weaponType: template.weapon_type,
        melee: template.melee,
        ranged: template.ranged,
        spell: template.spell,
        movement: template.movement,
        shootingRange: template.shooting_range,
        spellRange: template.spell_range,
        shootingTemplate: template.shooting_template,
        spellTemplate: template.spell_template,
        requiresLineOfSight: template.requires_line_of_sight,
        initiative: template.initiative,
        abilities: template.abilities_list,
        mounted: template.mounted
      }
    end

    def serialize_ability(ability)
      {
        id: ability.key,
        name: ability.name,
        category: ability.category,
        description: ability.description
      }
    end

    def serialize_upgrade(upgrade)
      {
        id: upgrade.upgrade_key,
        name: upgrade.name,
        category: upgrade.category,
        summary: upgrade.summary
      }
    end
  end
end