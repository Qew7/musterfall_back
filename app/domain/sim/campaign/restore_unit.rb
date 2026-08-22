module Sim
  module Campaign
    class RestoreUnit
      def self.call(campaign:, catalog:, player_id:, entity_id:, models: nil)
        new(campaign, catalog, player_id, entity_id, models).call
      end

      def initialize(campaign, catalog, player_id, entity_id, models)
        @campaign = campaign.deep_dup
        @catalog = catalog
        @player_id = player_id
        @entity_id = entity_id
        @models = models
      end

      def call
        player = @campaign.find_player(@player_id)
        return Result.failure("player not found", code: :not_found) unless player
        return Result.failure("player is not active") unless player[:status] == "active"

        entity = player[:roster].find { |entry| entry[:id] == @entity_id }
        return Result.failure("entity not found") unless entity

        template = @catalog.template(entity[:template_id])
        return Result.failure("unknown template") unless template

        model_health = entity.dig(:components, :health, :model_health).to_i
        return Result.failure("invalid model health") if model_health <= 0

        max_models = entity.dig(:components, :formation, :models).to_i
        current_models = Entities::Footprint.health_to_models(entity)
        missing = max_models - current_models
        return Result.failure("unit is already full") if missing <= 0

        affordable = RecruitAccess.affordable_restore_models(template, player[:treasury], missing)
        restore_count =
          if @models.nil?
            affordable
          else
            [ @models.to_i, missing, affordable ].min
          end
        return Result.failure("insufficient treasury") if restore_count <= 0

        cost = RecruitAccess.model_restore_cost(template, restore_count)
        player[:treasury] -= cost
        entity[:state][:current_health] = (current_models + restore_count) * model_health
        entity[:state][:is_routing] = false
        Entities::Footprint.sync_entity!(entity)
        Result.ok(@campaign)
      end
    end
  end
end
