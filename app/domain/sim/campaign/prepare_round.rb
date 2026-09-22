module Sim
  module Campaign
    class PrepareRound
      def self.call(campaign:, catalog:, rng:)
        new(campaign, catalog, rng).call
      end

      def initialize(campaign, catalog, rng)
        @campaign = campaign.deep_dup
        @catalog = catalog
        @rng = rng
      end

      def call
        assign_random_factions!
        roll_markets!
        prepare_bots!
        Result.ok(@campaign)
      end

      private

      def assign_random_factions!
        recruitable = @catalog.selectable_factions.select { |faction| @catalog.unit_templates(faction[:id]).any? }
        pool = recruitable.any? ? recruitable : @catalog.selectable_factions

        @campaign.players.each do |player|
          next if player[:faction_id].present?

          faction = @rng.pick(pool)
          next unless faction

          default_hero = @catalog.hero_templates(faction[:id]).first
          school_key = @rng.pick(Battle::Spells.schools_for(faction[:id])) if default_hero&.dig(:abilities)&.include?("wizard")
          result = AssignFaction.call(
            campaign: @campaign,
            catalog: @catalog,
            player_id: player[:id],
            faction_id: faction[:id],
            rng: @rng,
            school_key: school_key
          )
          @campaign = result.value if result.ok?
        end
      end

      def roll_markets!
        @campaign.players.each do |player|
          next unless player[:status] == "active" && player[:faction_id].present?

          RecruitAccess.roll_offer!(player, @catalog, @rng)
        end
      end

      def prepare_bots!
        @campaign.players.each do |player|
          next unless player[:is_bot] && player[:status] == "active" && player[:faction_id].present?

          result = BotRecruit.call(
            campaign: @campaign,
            catalog: @catalog,
            player_id: player[:id],
            rng: @rng
          )
          next if result.failure?

          auto_level_general!(player[:id])
          auto_deploy_bot!(player[:id])
        end
      end

      def auto_level_general!(player_id)
        4.times do
          player = @campaign.find_player(player_id)
          general = Array(player&.dig(:roster)).find { |entry| entry.dig(:components, :hero, :general) }
          break unless general && Upgrades::Draft.level_ready?(general)

          general[:components][:progression][:pending_draft] = Upgrades::Draft.roll(general, @catalog, @rng)
          upgrade_id = general.dig(:components, :progression, :pending_draft)&.first
          break unless upgrade_id
          break unless Upgrades::Draft.apply!(general, upgrade_id, catalog: @catalog)

          Entities::Footprint.sync_entity!(general)
        end
      end

      def auto_deploy_bot!(player_id)
        player = @campaign.find_player(player_id)
        return unless player

        Geometry::Deployment.pack_roster!(player[:roster])
      end
    end
  end
end
