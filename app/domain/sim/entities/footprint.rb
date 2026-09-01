module Sim
  module Entities
    module Footprint
      module_function

      def health_to_models(entity)
        model_health = entity.dig(:components, :health, :model_health).to_i
        return 0 if model_health <= 0

        [ (entity.dig(:state, :current_health).to_f / model_health).ceil, 0 ].max
      end

      def formation_models_remaining(entity)
        return 0 if entity.dig(:state, :current_health).to_i <= 0
        return entity.dig(:components, :formation, :models).to_i if entity[:kind] == "hero"
        return 1 if entity.dig(:components, :formation, :model_class).to_s == "machine"

        health_to_models(entity)
      end

      def sync_entity!(entity)
        models_remaining = formation_models_remaining(entity)
        formation = entity[:components][:formation]
        metrics = Geometry::Formation.metrics(
          models_remaining: models_remaining,
          frontage: formation[:frontage],
          max_files: formation[:max_files],
          model_width: formation[:model_width],
          model_depth: formation[:model_depth]
        )
        formation[:files] = metrics[:files]
        formation[:ranks] = metrics[:ranks]
        formation[:width] = metrics[:footprint_width]
        formation[:depth] = metrics[:footprint_depth]
        entity
      end

      def deployable?(entity)
        entity.dig(:components, :formation, :row) != "reserve" && entity.dig(:state, :current_health).to_i > 0
      end
    end
  end
end
