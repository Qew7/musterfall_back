module Sim
  module Campaign
    class Recruit
      def self.call(campaign:, catalog:, player_id:, template_id:, rng: Rng::Seeded.new(0), school_key: nil)
        new(campaign, catalog, player_id, template_id, rng, school_key).call
      end

      def initialize(campaign, catalog, player_id, template_id, rng, school_key)
        @campaign = campaign.deep_dup
        @catalog = catalog
        @player_id = player_id
        @template_id = template_id
        @rng = rng
        @school_key = school_key
      end

      def call
        player = @campaign.find_player(@player_id)
        template = @catalog.template(@template_id)
        return Result.failure("player not found", code: :not_found) unless player
        return Result.failure("player is not active") unless player[:status] == "active"
        return Result.failure("unknown template") unless template
        return Result.failure("faction required") if player[:faction_id].blank?
        return Result.failure("template faction mismatch") unless template[:faction_id] == player[:faction_id]
        return Result.failure("insufficient treasury") if player[:treasury] < template[:cost]

        loadout = MagicLoadout.build(
          template: template,
          faction_id: player[:faction_id],
          school_key: @school_key,
          rng: @rng
        )
        return loadout if loadout.failure?

        factory = Entities::Factory.new(@catalog, id_sequence: { value: @campaign.id_sequence })
        entity = template[:kind] == "hero" ? factory.create_hero(template[:id], player[:id]) : factory.create_unit(template[:id], player[:id])
        entity[:components][:hero]&.merge!(loadout.value)
        @campaign.id_sequence = factory.sequence_value
        player[:treasury] -= template[:cost]
        player[:roster] << entity
        Result.ok(@campaign)
      end
    end
  end
end
