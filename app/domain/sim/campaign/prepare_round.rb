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

          result = AssignFaction.call(campaign: @campaign, catalog: @catalog, player_id: player[:id], faction_id: faction[:id])
          @campaign = result.value if result.ok?
        end
      end

      def prepare_bots!
        @campaign.players.each do |player|
          next unless player[:is_bot] && player[:status] == "active" && player[:faction_id].present?

          recruit_bot_units!(player)
          result = Deploy.call(campaign: @campaign, player_id: player[:id], action: "auto")
          @campaign = result.value if result.ok?
        end
      end

      def recruit_bot_units!(player)
        unit_templates = @catalog.unit_templates(player[:faction_id]).sort_by { |template| template[:cost] }
        cheapest = unit_templates.first&.dig(:cost)
        return unless cheapest

        while player[:treasury] >= cheapest
          affordable = unit_templates.select { |template| template[:cost] <= player[:treasury] }
          selected = @rng.pick(affordable)
          break unless selected

          result = Recruit.call(campaign: @campaign, catalog: @catalog, player_id: player[:id], template_id: selected[:id])
          break unless result.ok?

          @campaign = result.value
          player = @campaign.find_player(player[:id])
        end
      end
    end
  end
end
