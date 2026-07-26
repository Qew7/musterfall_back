module Sim
  module Geometry
    module Formation
      module_function

      def metrics(models_remaining:, frontage:, max_files:, model_width:, model_depth:)
        if models_remaining <= 0
          return {
            files: 0,
            ranks: 0,
            footprint_width: 0,
            footprint_depth: 0,
            grid_width: 0,
            grid_depth: 0
          }
        end

        files = [ max_files, frontage, models_remaining ].min
        files = 1 if files < 1
        ranks = (models_remaining.to_f / files).ceil

        {
          files: files,
          ranks: ranks,
          footprint_width: files * model_width,
          footprint_depth: ranks * model_depth,
          grid_width: files * model_width,
          grid_depth: ranks * model_depth
        }
      end
    end
  end
end
