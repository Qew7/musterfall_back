module Sim
  module Upgrades
    module Draft
      MODEL_FOOTPRINTS = {
        "infantry" => { width: 1, depth: 1 },
        "cavalry" => { width: 1, depth: 2 },
        "monster" => { width: 2, depth: 2 }
      }.freeze

      MOUNTS = {
        "warhorse" => { model_class: "cavalry", movement: 7, melee: 1, abilities: %w[fast momentumCharge] },
        "winged_mount" => { model_class: "monster", movement: 20, melee: 1, health: 1, abilities: %w[flying momentumCharge monster] },
        "boar_mount" => { model_class: "cavalry", movement: 7, melee: 1, abilities: %w[fast boarCharge momentumCharge] },
        "dragon_mount" => { model_class: "monster", movement: 20, melee: 2, health: 1, abilities: %w[flying fear ferocious] },
        "dread_steed" => { model_class: "cavalry", movement: 7, melee: 1, abilities: %w[fast fear momentumCharge] },
        "giant_bat" => { model_class: "monster", movement: 20, melee: 1, health: 1, abilities: %w[flying fear undead] },
        "forest_stag" => { model_class: "cavalry", movement: 7, melee: 2, health: 1, abilities: %w[fast fearless wildborn momentumCharge] },
        "sky_hart" => { model_class: "monster", movement: 20, melee: 1, health: 1, abilities: %w[flying forestborn wildborn fearless] },
        "chaos_steed" => { model_class: "cavalry", movement: 7, melee: 1, health: 1, abilities: %w[fast fear momentumCharge] }
      }.freeze

      EFFECTS = {
        "rune_blade" => ->(hero) {
          hero[:components][:combat][:melee] += 2
          hero[:components][:combat][:weapon_type] = "slash"
        },
        "meteor_hammer" => ->(hero) {
          hero[:components][:combat][:melee] += 2
          hero[:components][:combat][:weapon_type] = "blunt"
        },
        "dragonspear" => ->(hero) {
          hero[:components][:combat][:melee] += 1
          hero[:components][:combat][:weapon_type] = "puncture"
          hero[:components][:abilities] << "antiLarge"
        },
        "gilded_plate" => ->(hero) {
          hero[:components][:combat][:armor_type] = "heavy"
          hero[:components][:health][:max] += 1
          hero[:state][:current_health] += 1
        },
        "shadow_cloak" => ->(hero) {
          hero[:components][:abilities].concat(%w[skirmisher dodge])
        },
        "war_banner" => ->(hero) {
          hero[:components][:abilities] << "bannerAura"
        },
        "arcane_focus" => ->(hero) {
          hero[:components][:combat][:spell] += 2
        },
        "scaled_hide" => ->(hero) {
          hero[:components][:combat][:armor_type] = "magic"
          hero[:components][:abilities] << "regen"
        },
        "longbow_mastery" => ->(hero) {
          hero[:components][:combat][:ranged] += 2
          hero[:components][:abilities] << "precision"
        },
        "veteran_drill" => ->(hero) {
          hero[:components][:health][:max] += 1
          hero[:state][:current_health] += 1
          hero[:components][:combat][:melee] += 1
        },
        "battle_prayer" => ->(hero) {
          hero[:components][:abilities] << "resoluteAura"
        },
        "hellfire_breath" => ->(hero) {
          hero[:components][:combat][:ranged] += 2
          hero[:components][:combat][:weapon_type] = "breath"
        },
        "toxin_coating" => ->(hero) {
          hero[:components][:abilities] << "toxin"
        },
        "imperial_halberd" => ->(hero) {
          hero[:components][:combat][:melee] += 3
          hero[:components][:combat][:weapon_type] = "puncture"
          hero[:components][:abilities] << "supportRank"
        },
        "imperial_drill" => ->(hero) {
          hero[:components][:health][:max] += 1
          hero[:state][:current_health] += 1
          hero[:components][:combat][:melee] += 2
        },
        "crown_blessing" => ->(hero) {
          hero[:components][:health][:max] += 1
          hero[:state][:current_health] += 1
          hero[:components][:abilities].concat(%w[resoluteAura disciplined])
        },
        "warhorse" => ->(hero) { apply_mount!(hero, "warhorse") },
        "winged_mount" => ->(hero) { apply_mount!(hero, "winged_mount") },
        "brutal_cleaver" => ->(hero) {
          hero[:components][:combat][:melee] += 3
          hero[:components][:abilities] << "ferocious"
        },
        "mob_drill" => ->(hero) {
          hero[:components][:health][:max] += 1
          hero[:state][:current_health] += 1
          hero[:components][:combat][:melee] += 2
        },
        "mob_rule" => ->(hero) {
          hero[:components][:abilities].concat(%w[bannerAura ferocious])
        },
        "boar_mount" => ->(hero) { apply_mount!(hero, "boar_mount") },
        "grave_blade" => ->(hero) {
          hero[:components][:combat][:melee] += 2
          hero[:components][:abilities] << "regen"
        },
        "deathly_resilience" => ->(hero) {
          hero[:components][:health][:max] += 1
          hero[:state][:current_health] += 1
          hero[:components][:combat][:melee] += 1
          hero[:components][:combat][:spell] += 1
        },
        "necromantic_vigor" => ->(hero) {
          hero[:components][:health][:max] += 1
          hero[:state][:current_health] += 1
          hero[:components][:abilities].concat(%w[regen fear])
        },
        "dread_steed" => ->(hero) { apply_mount!(hero, "dread_steed") },
        "heartwood_bow" => ->(hero) {
          hero[:components][:combat][:ranged] += 3
          hero[:components][:abilities].concat(%w[precision forestborn ranged])
        },
        "wild_growth" => ->(hero) {
          hero[:components][:health][:max] += 1
          hero[:state][:current_health] += 1
          hero[:components][:combat][:melee] += 1
          hero[:components][:combat][:ranged] += 1
        },
        "spirit_bark" => ->(hero) {
          hero[:components][:abilities].concat(%w[forestkin regen])
        },
        "forest_stag" => ->(hero) { apply_mount!(hero, "forest_stag") },
        "runescarred_blade" => ->(hero) {
          hero[:components][:combat][:melee] += 3
          hero[:components][:abilities] << "runeArmor"
        },
        "chaos_mutation" => ->(hero) {
          hero[:components][:health][:max] += 1
          hero[:state][:current_health] += 1
          hero[:components][:combat][:melee] += 2
        },
        "dark_gift" => ->(hero) {
          hero[:components][:health][:max] += 1
          hero[:state][:current_health] += 1
          hero[:components][:combat][:spell] += 2
          hero[:components][:abilities] << "fear"
        },
        "chaos_steed" => ->(hero) { apply_mount!(hero, "chaos_steed") },
        "dragon_mount" => ->(hero) { apply_mount!(hero, "dragon_mount") },
        "giant_bat" => ->(hero) { apply_mount!(hero, "giant_bat") },
        "demon_form" => ->(hero) {
          apply_transform!(hero, model_class: "monster", movement: 20, melee: 2, health: 2, spell: 1, abilities: %w[flying fear momentumCharge monster])
        },
        "sky_hart" => ->(hero) { apply_mount!(hero, "sky_hart") }
      }.freeze

      # Win = 1 level, loss = half. Stored as integer credits (2 = full level).
      LEVEL_UNIT = 2
      WIN_CREDIT = 2
      LOSS_CREDIT = 1

      module_function

      def apply_mount!(hero, upgrade_id)
        revert_mount!(hero)
        spec = MOUNTS.fetch(upgrade_id)
        hero[:components][:hero][:mount_id] = upgrade_id
        hero[:components][:hero][:mounted] = true
        hero[:components][:hero][:base_movement] ||= hero.dig(:components, :combat, :movement).to_i
        hero[:components][:combat][:movement] = spec.fetch(:movement)
        hero[:components][:combat][:melee] += spec.fetch(:melee, 0)
        hero[:components][:combat][:ranged] += spec.fetch(:ranged, 0)
        if (health = spec.fetch(:health, 0)).positive?
          hero[:components][:health][:max] += health
          hero[:state][:current_health] += health
        end
        hero[:components][:abilities].concat(spec.fetch(:abilities, []))
        footprint = MODEL_FOOTPRINTS.fetch(spec.fetch(:model_class))
        formation = hero[:components][:formation]
        formation[:model_class] = spec.fetch(:model_class)
        formation[:model_width] = footprint[:width]
        formation[:model_depth] = footprint[:depth]
      end

      def revert_mount!(hero)
        mount_id = hero.dig(:components, :hero, :mount_id)
        return unless mount_id

        spec = MOUNTS.fetch(mount_id)
        hero[:components][:combat][:movement] = hero.dig(:components, :hero, :base_movement) || 3
        hero[:components][:combat][:melee] -= spec.fetch(:melee, 0)
        hero[:components][:combat][:ranged] -= spec.fetch(:ranged, 0)
        if (health = spec.fetch(:health, 0)).positive?
          hero[:components][:health][:max] -= health
          hero[:state][:current_health] = [ hero[:state][:current_health].to_i - health, 1 ].max
        end
        abilities = hero[:components][:abilities]
        spec.fetch(:abilities, []).each { |key| abilities.delete(key) }
        hero[:components][:hero][:mount_id] = nil
        hero[:components][:hero][:mounted] = false
        reset_footprint!(hero) unless hero.dig(:components, :hero, :transformed)
      end

      def reset_footprint!(hero)
        footprint = MODEL_FOOTPRINTS.fetch("infantry")
        formation = hero[:components][:formation]
        formation[:model_class] = "infantry"
        formation[:model_width] = footprint[:width]
        formation[:model_depth] = footprint[:depth]
      end

      def experience_threshold(_hero = nil)
        LEVEL_UNIT
      end

      def level_ready?(hero)
        return false unless hero.dig(:components, :hero, :general)

        progression = hero.dig(:components, :progression)
        return false unless progression

        available = progression[:experience].to_i - progression[:spent_experience].to_i
        available >= experience_threshold
      end

      def grant_battle_credit!(player, credit)
        general = Array(player[:roster]).find { |entry| entry[:kind] == "hero" && entry.dig(:components, :hero, :general) }
        return unless general

        general[:components][:progression][:experience] = general.dig(:components, :progression, :experience).to_i + credit.to_i
      end

      def roll(hero, catalog, rng)
        faction_id = hero.dig(:components, :identity, :faction_id)
        blocked = hero.dig(:components, :progression, :picked_upgrade_ids).to_a
        common = eligible_pool(catalog.hero_upgrades, faction_id: nil, blocked: blocked, hero: hero)
        faction = eligible_pool(catalog.hero_upgrades, faction_id: faction_id, blocked: blocked, hero: hero)

        picks = []
        picks << pick_one(common, rng)
        picks << pick_one(faction, rng)
        third_pool = rng.rand(2).zero? ? faction : common
        picks << pick_one(third_pool, rng, exclude: picks)
        picks.compact!
        picks.uniq!
        backfill_picks(picks, common, faction, rng)
      end

      def apply_transform!(hero, model_class:, movement:, abilities: [], melee: 0, health: 0, spell: 0, ranged: 0)
        hero[:components][:hero][:transformed] = true
        hero[:components][:combat][:movement] = movement
        hero[:components][:combat][:melee] += melee
        hero[:components][:combat][:ranged] += ranged
        hero[:components][:combat][:spell] += spell
        if health.positive?
          hero[:components][:health][:max] += health
          hero[:state][:current_health] += health
        end
        hero[:components][:abilities].concat(abilities)
        footprint = MODEL_FOOTPRINTS.fetch(model_class)
        formation = hero[:components][:formation]
        formation[:model_class] = model_class
        formation[:model_width] = footprint[:width]
        formation[:model_depth] = footprint[:depth]
      end

      def next_level(hero)
        hero.dig(:components, :progression, :level).to_i + 1
      end

      def upgrade_eligible?(entry, hero, blocked:)
        return false if blocked.include?(entry[:id])
        return false if entry[:min_level].to_i > next_level(hero)
        return false if entry[:general_only] && !hero.dig(:components, :hero, :general)
        return false if entry[:category] == "transform" && hero.dig(:components, :hero, :transformed)

        true
      end

      def eligible_pool(upgrades, faction_id:, blocked:, hero:)
        upgrades.select do |entry|
          next false unless entry[:faction_id] == faction_id
          next false unless upgrade_eligible?(entry, hero, blocked: blocked)

          true
        end
      end

      def pick_one(pool, rng, exclude: [])
        candidates = pool.reject { |entry| exclude.include?(entry[:id]) }
        return nil if candidates.empty?

        candidates[rng.rand(candidates.length)][:id]
      end

      def backfill_picks(picks, common, faction, rng)
        merged = (common + faction).uniq { |entry| entry[:id] }
        while picks.length < 3 && merged.any?
          candidate = pick_one(merged, rng, exclude: picks)
          break unless candidate

          picks << candidate
        end
        picks.first(3)
      end

      def apply!(hero, upgrade_id, catalog: nil)
        effect = EFFECTS[upgrade_id]
        return false unless effect

        meta = catalog&.hero_upgrades&.find { |entry| entry[:id] == upgrade_id }
        blocked = hero.dig(:components, :progression, :picked_upgrade_ids).to_a
        return false if meta && !upgrade_eligible?(meta, hero, blocked: blocked)
        cost = experience_threshold
        effect.call(hero)
        progression = hero[:components][:progression]
        progression[:level] += 1
        progression[:spent_experience] += cost
        progression[:picked_upgrade_ids] << upgrade_id unless meta&.dig(:repeatable)
        progression[:pending_draft] = []
        true
      end
    end
  end
end
