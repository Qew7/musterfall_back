module Sim
  module Campaign
    class AssignFaction
      def self.call(campaign:, catalog:, player_id:, faction_id:, rng: Rng::Seeded.new(0), school_key: nil, template_id: nil)
        new(campaign, catalog, player_id, faction_id, rng, school_key, template_id).call
      end

      def initialize(campaign, catalog, player_id, faction_id, rng, school_key, template_id)
        @campaign = campaign.deep_dup
        @catalog = catalog
        @player_id = player_id
        @faction_id = faction_id
        @rng = rng
        @school_key = school_key
        @template_id = template_id
      end

      def call
        player = @campaign.find_player(@player_id)
        return Result.failure("player not found", code: :not_found) unless player
        return Result.failure("unknown faction") unless @catalog.faction(@faction_id)
        return Result.ok(@campaign) if player[:faction_id] == @faction_id && @template_id.blank?

        default_hero = starter_hero
        return Result.failure("starter hero is not in faction") if @template_id.present? && default_hero.nil?

        loadout = default_hero ? MagicLoadout.build(
          template: default_hero,
          faction_id: @faction_id,
          school_key: @school_key,
          rng: @rng
        ) : Result.ok({})
        return loadout if loadout.failure?

        apply_faction_assignment!(player, default_hero, loadout.value)
        Result.ok(@campaign)
      end

      private

      def starter_hero
        heroes = @catalog.hero_templates(@faction_id)
        return heroes.first if @template_id.blank?

        heroes.find { |hero| hero[:id] == @template_id.to_s }
      end

      def apply_faction_assignment!(player, default_hero, loadout)
        player[:faction_id] = @faction_id
        player[:roster] = []
        player[:treasury] = Constants::STARTING_TREASURY
        return unless default_hero

        factory = Entities::Factory.new(@catalog, id_sequence: { value: @campaign.id_sequence })
        hero = factory.create_hero(default_hero[:id], player[:id], free: true)
        hero[:components][:hero].merge!(loadout)
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
