module Balance
  module Synthetic
    module Army
      module_function

      def build!(catalog:, faction_id:, budget:, hero_level:, rng:, player_id:, recruit_strategy: "balanced")
        campaign = mini_campaign(player_id)
        school_key = wizard_school(catalog, faction_id, rng)
        assigned = Sim::Campaign::AssignFaction.call(
          campaign: campaign,
          catalog: catalog,
          player_id: player_id,
          faction_id: faction_id,
          rng: rng,
          school_key: school_key
        )
        raise assigned.error unless assigned.ok?

        campaign = assigned.value
        player = campaign.find_player(player_id)
        player[:treasury] = budget.to_i
        player[:recruit_access] = 3
        player[:recruit_strategy] = recruit_strategy

        shopped = Sim::Campaign::BotRecruit.call(
          campaign: campaign,
          catalog: catalog,
          player_id: player_id,
          rng: rng
        )
        raise shopped.error unless shopped.ok?

        player = shopped.value.find_player(player_id)
        level_hero!(player, hero_level.to_i, catalog, rng)
        deploy!(player)
        {
          id: player[:id],
          name: player[:name],
          is_bot: true,
          faction_id: player[:faction_id],
          roster: Marshal.load(Marshal.dump(player[:roster]))
        }
      end

      def wizard_school(catalog, faction_id, rng)
        default_hero = catalog.hero_templates(faction_id).first
        return nil unless default_hero&.dig(:abilities)&.include?("wizard")

        rng.pick(Sim::Battle::Spells.schools_for(faction_id))&.to_s
      end

      def mini_campaign(player_id)
        Sim::Campaign::State.new(
          round: 1,
          players: [
            {
              id: player_id,
              name: player_id,
              is_bot: true,
              status: "active",
              faction_id: nil,
              treasury: 0,
              recruit_access: 0,
              recruit_strategy: "balanced",
              roster: [],
              victories: 0,
              round_notes: []
            }
          ],
          id_sequence: 0
        )
      end

      def level_hero!(player, target_level, catalog, rng)
        general = Array(player[:roster]).find { |entry| entry.dig(:components, :hero, :general) }
        return unless general

        target_level = [ target_level, 1 ].max
        while general.dig(:components, :progression, :level).to_i < target_level
          needed = Sim::Upgrades::Draft.experience_threshold(general) -
            (general.dig(:components, :progression, :experience).to_i - general.dig(:components, :progression, :spent_experience).to_i)
          general[:components][:progression][:experience] += [ needed, Sim::Upgrades::Draft::LEVEL_UNIT ].max if needed.positive?

          break unless Sim::Upgrades::Draft.level_ready?(general)

          general[:components][:progression][:pending_draft] = Sim::Upgrades::Draft.roll(general, catalog, rng)
          upgrade_id = general.dig(:components, :progression, :pending_draft)&.first
          break unless upgrade_id
          break unless Sim::Upgrades::Draft.apply!(general, upgrade_id, catalog: catalog)

          Sim::Entities::Footprint.sync_entity!(general)
        end
      end

      def deploy!(player)
        Sim::Geometry::Deployment.pack_roster!(player[:roster])
      end
    end
  end
end
