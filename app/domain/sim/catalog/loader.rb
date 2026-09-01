module Sim
  class Catalog
    class Loader
      def self.load
        @cache ||= new.load
      end

      def self.reset!
        @cache = nil
      end

      def load
        Catalog.new(
          formation_rules: { max_files: ArmyTemplate::MAX_FORMATION_FILES },
          model_classes: ArmyTemplate::MODEL_CLASSES.map { |key, footprint| serialize_model_class(key, footprint) },
          factions: Faction.order(:position).includes(:units, :heroes).map { |faction| serialize_faction(faction) },
          units: Unit.includes(:faction, :abilities_records).order(:name).map { |template| serialize_template(template) },
          heroes: Hero.includes(:faction, :abilities_records).order(:name).map { |template| serialize_template(template) },
          abilities: Ability.order(:key).map { |ability| serialize_ability(ability) },
          hero_upgrades: HeroUpgrade.includes(:faction).order(:position).map { |upgrade| serialize_upgrade(upgrade) }
        )
      end

      private

      def serialize_faction(faction)
        {
          id: faction.slug,
          name: faction.name,
          vibe: faction.vibe,
          passive: faction.passive,
          color: faction.color,
          unit_pool: faction.units.map(&:template_key),
          hero_pool: faction.heroes.map(&:template_key)
        }
      end

      def serialize_template(template)
        {
          id: template.template_key,
          kind: template.kind,
          faction_id: template.faction.slug,
          name: template.name,
          cost: template.cost,
          recruit_tier: template.kind == "hero" ? "hero" : template.recruit_tier,
          models: template.models,
          model_health: template.model_health,
          frontage: template.width,
          model_class: template.model_class,
          model_base_width: template.effective_model_base_width,
          model_base_depth: template.effective_model_base_depth,
          armor_type: template.armor_type,
          weapon_type: template.weapon_type,
          melee: template.melee,
          ranged: template.ranged,
          spell: template.spell,
          skill: template.skill,
          movement: template.movement,
          morale: template.morale,
          shooting_range: template.shooting_range,
          spell_range: template.spell_range,
          shooting_template: template.shooting_template,
          spell_template: template.spell_template,
          requires_line_of_sight: template.requires_line_of_sight,
          initiative: template.initiative,
          attacks: template.attacks,
          missile_attacks: template.missile_attacks,
          abilities: template.abilities_list,
          mounted: template.mounted
        }
      end

      def serialize_model_class(key, footprint)
        {
          id: key,
          base_width: footprint.fetch(:width),
          base_depth: footprint.fetch(:depth)
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
          summary: upgrade.summary,
          faction_id: upgrade.faction&.slug,
          repeatable: upgrade.repeatable,
          min_level: upgrade.min_level,
          general_only: upgrade.general_only
        }
      end
    end
  end
end
