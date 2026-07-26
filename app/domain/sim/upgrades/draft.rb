module Sim
  module Upgrades
    module Draft
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
        "gryphon_hide" => ->(hero) {
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
          hero[:components][:abilities] << "steadfastAura"
        },
        "hellfire_breath" => ->(hero) {
          hero[:components][:combat][:ranged] += 2
          hero[:components][:combat][:weapon_type] = "breath"
        }
      }.freeze

      module_function

      def experience_threshold(hero)
        hero.dig(:components, :progression, :level).to_i + 3
      end

      def level_ready?(hero)
        progression = hero.dig(:components, :progression)
        return false unless progression

        available = progression[:experience].to_i - progression[:spent_experience].to_i
        available >= experience_threshold(hero)
      end

      def roll(hero, catalog, rng)
        blocked = hero.dig(:components, :progression, :picked_upgrade_ids).to_a
        pool = catalog.hero_upgrades.reject { |entry| blocked.include?(entry[:id]) }.map { |entry| entry[:id] }
        picks = []
        while picks.length < 3 && pool.any?
          index = rng.rand(pool.length)
          picks << pool.delete_at(index)
        end
        picks
      end

      def apply!(hero, upgrade_id)
        effect = EFFECTS[upgrade_id]
        return false unless effect

        cost = experience_threshold(hero)
        effect.call(hero)
        progression = hero[:components][:progression]
        progression[:level] += 1
        progression[:spent_experience] += cost
        progression[:picked_upgrade_ids] << upgrade_id
        progression[:pending_draft] = []
        true
      end
    end
  end
end
