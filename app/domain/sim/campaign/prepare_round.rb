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

        deployable = player[:roster]
          .select { |entry| entry.dig(:state, :current_health).to_i > 0 }
          .reject { |entry| entry[:kind] == "hero" && entry[:state][:attached_to] }
          .sort_by { |entity| bot_deploy_sort_key(entity) }

        deployable.each_with_index do |entity, index|
          row = Constants::BATTLE_ROWS[[ 2, index / 3 ].min]
          lane = Constants::LANE_ORDER[index % Constants::LANE_ORDER.length]
          clear = Geometry::Deployment.find_clear_position(entity, row, lane, player[:roster], ignore_id: entity[:id])
          next unless clear

          formation = entity[:components][:formation]
          formation[:facing] = clear[:facing] if clear[:facing]
          formation[:x] = clear[:x]
          formation[:y] = clear[:y]
          slots = Geometry::Battlefield.sync_formation_slots_from_deployment(formation)
          formation[:lane] = slots[:lane]
          formation[:row] = slots[:row]
        end
      end

      def bot_deploy_sort_key(entity)
        Entities::Footprint.sync_entity!(entity)
        formation = entity[:components][:formation]
        area = -(formation[:width].to_f * formation[:depth].to_f)

        if entity[:kind] == "hero"
          return [ 0, 0, area ] if entity.dig(:components, :hero, :general)

          return [ 1, 0, area ]
        end

        [ 2, 0, area ]
      end
    end
  end
end
