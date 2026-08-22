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
        prepare_bots!
        Result.ok(@campaign)
      end

      private

      def assign_random_factions!
        recruitable = @catalog.factions.select { |faction| @catalog.unit_templates(faction[:id]).any? }
        pool = recruitable.any? ? recruitable : @catalog.factions

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

      def prepare_bots!
        @campaign.players.each do |player|
          next unless player[:is_bot] && player[:status] == "active" && player[:faction_id].present?

          result = BotRecruit.call(
            campaign: @campaign,
            catalog: @catalog,
            player_id: player[:id],
            rng: @rng
          )
          @campaign = result.value if result.ok?

          auto_level_general!(player[:id])

          deploy = Deploy.call(campaign: @campaign, player_id: player[:id], action: "auto")
          @campaign = deploy.value if deploy.ok?
        end
      end

      def auto_level_general!(player_id)
        4.times do
          player = @campaign.find_player(player_id)
          general = Array(player&.dig(:roster)).find { |entry| entry.dig(:components, :hero, :general) }
          break unless general && Upgrades::Draft.level_ready?(general)

          prepared = HeroDraft.prepare(
            campaign: @campaign,
            catalog: @catalog,
            player_id: player_id,
            hero_id: general[:id],
            rng: @rng
          )
          break unless prepared.ok?

          @campaign = prepared.value
          upgrade_id = @campaign.find_entity(player_id, general[:id]).dig(:components, :progression, :pending_draft).first
          break unless upgrade_id

          picked = HeroDraft.pick(
            campaign: @campaign,
            player_id: player_id,
            hero_id: general[:id],
            upgrade_id: upgrade_id
          )
          break unless picked.ok?

          @campaign = picked.value
        end
      end
    end
  end
end
