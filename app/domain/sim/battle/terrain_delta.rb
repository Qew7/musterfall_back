module Sim
  module Battle
    # Single entry for mutating battle terrain and recording replay deltas.
    module TerrainDelta
      module_function

      def append!(holder, operation, feature)
        return unless holder && feature

        change = { operation: operation.to_s, feature: feature }
        if holder.is_a?(Array)
          holder << change
        else
          holder[:terrain_delta] = Array(holder[:terrain_delta]) << change
        end
        change
      end

      def add!(terrain, holder, **kwargs)
        feature = SpellWorld.add_terrain!(terrain, **kwargs)
        append!(holder, :add, feature) if feature && holder
        feature
      end

      def remove!(terrain, feature, holder:)
        removed = SpellWorld.remove_terrain!(terrain, feature)
        append!(holder, :remove, removed) if removed && holder
        removed
      end
    end
  end
end
