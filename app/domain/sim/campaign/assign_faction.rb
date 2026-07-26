module Sim
  module Campaign
    class AssignFaction
      def self.call(campaign:, catalog:, player_id:, faction_id:)
        new(campaign, catalog, player_id, faction_id).call
      end

      def initialize(campaign, catalog, player_id, faction_id)
        @campaign = campaign.deep_dup
        @catalog = catalog
        @player_id = player_id
        @faction_id = faction_id
      end

      def call
        player = @campaign.find_player(@player_id)
        return Result.failure("player not found", code: :not_found) unless player
        return Result.failure("unknown faction") unless @catalog.faction(@faction_id)
        return Result.ok(@campaign) if player[:faction_id] == @faction_id

        apply_faction_assignment!(player)
        Result.ok(@campaign)
      end

      private

      def apply_faction_assignment!(player)
        player[:faction_id] = @faction_id
        player[:roster] = []
        player[:treasury] = Constants::STARTING_TREASURY
        default_hero = @catalog.hero_templates(@faction_id).first
        return unless default_hero

        factory = Entities::Factory.new(@catalog, id_sequence: { value: @campaign.id_sequence })
        hero = factory.create_hero(default_hero[:id], player[:id], free: true)
        @campaign.id_sequence = factory.sequence_value
        apply_formation_slot!(hero, "support", "center")
        player[:roster] << hero
      end

      def apply_formation_slot!(entity, row, lane)
        position = Geometry::Battlefield.default_deployment(row, lane)
        formation = entity[:components][:formation]
        formation[:row] = row
        formation[:lane] = lane
        formation[:x] = position[:x]
        formation[:y] = position[:y]
        formation[:facing] = position[:facing]
      end
    end
  end
end
