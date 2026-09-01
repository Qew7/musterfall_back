require "digest"

module Balance
  module CatalogFingerprint
    RULES_ROOT = Rails.root.join("app/domain/sim/battle/rules").freeze

    module_function

    def catalog_hash
      Digest::SHA256.hexdigest(catalog_payload)
    end

    def rules_hash
      Digest::SHA256.hexdigest(rules_payload)
    end

    def catalog_payload
      rows = []
      rows << factions_payload
      rows << templates_payload
      rows << upgrades_payload
      rows << abilities_payload
      rows.join("\n")
    end

    def rules_payload
      paths = Dir.glob(RULES_ROOT.join("**", "*.rb")).sort
      paths.map { |path|
        relative = Pathname.new(path).relative_path_from(Rails.root).to_s
        "#{relative}:#{Digest::SHA256.file(path).hexdigest}"
      }.join("\n")
    end

    def factions_payload
      Faction.order(:slug).map { |faction|
        [ faction.slug, faction.name, faction.passive, faction.color, faction.position ].join("|")
      }.join("\n")
    end

    def templates_payload
      ArmyTemplate.includes(:faction, :abilities_records).order(:template_key).map { |template|
        [
          template.template_key,
          template.kind,
          template.faction.slug,
          template.cost,
          template.melee,
          template.ranged,
          template.spell,
          template.skill,
          template.movement,
          template.morale,
          template.attacks,
          template.missile_attacks,
          template.model_health,
          template.models,
          template.abilities_list.sort.join(",")
        ].join("|")
      }.join("\n")
    end

    def upgrades_payload
      HeroUpgrade.includes(:faction).order(:upgrade_key).map { |upgrade|
        [
          upgrade.upgrade_key,
          upgrade.faction&.slug,
          upgrade.category,
          upgrade.repeatable,
          upgrade.min_level,
          upgrade.general_only
        ].join("|")
      }.join("\n")
    end

    def abilities_payload
      Ability.order(:key).map { |ability|
        [ ability.key, ability.category, ability.name ].join("|")
      }.join("\n")
    end
  end
end
