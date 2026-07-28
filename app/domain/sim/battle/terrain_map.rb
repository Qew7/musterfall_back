module Sim
  module Battle
    # Deterministic battlefield terrain for a campaign round (shared by deploy preview + fights).
    module TerrainMap
      TYPE_WEIGHTS = [
        [ "house", 2 ],
        [ "lake", 2 ],
        [ "difficult", 3 ],
        [ "forest", 3 ]
      ].freeze

      SIZE_RANGES = {
        "house" => { width: [ 2.0, 3.5 ], depth: [ 2.0, 3.5 ] },
        "lake" => { width: [ 3.0, 5.5 ], depth: [ 2.0, 4.0 ] },
        "difficult" => { width: [ 3.0, 5.0 ], depth: [ 3.0, 4.5 ] },
        "forest" => { width: [ 4.0, 6.5 ], depth: [ 3.0, 5.5 ] }
      }.freeze

      MIN_FEATURES = 3
      MAX_FEATURES = 6
      MAX_ATTEMPTS = 80
      EDGE_PAD = 1.0
      TARGET_COVERAGE = 0.22

      module_function

      def map_seed(rng_seed:, round:)
        (rng_seed.to_i + (round.to_i * 1_000_003)) & 0x7FFFFFFF
      end

      def generate(seed:)
        rng = Rng::Seeded.new(seed)
        cfg = Geometry::Battlefield::CONFIG
        depth = cfg[:deployment_depth].to_f
        width = cfg[:width].to_f
        height = cfg[:height].to_f
        zone = {
          x_min: depth + EDGE_PAD,
          x_max: width - depth - EDGE_PAD,
          y_min: EDGE_PAD,
          y_max: height - EDGE_PAD
        }
        zone_area = [ (zone[:x_max] - zone[:x_min]) * (zone[:y_max] - zone[:y_min]), 1.0 ].max
        count = MIN_FEATURES + rng.rand((MAX_FEATURES - MIN_FEATURES) + 1)
        features = []
        covered = 0.0

        count.times do |index|
          break if covered / zone_area >= TARGET_COVERAGE

          feature = place_feature(rng, zone, features, index)
          next unless feature

          features << feature
          covered += feature[:width] * feature[:depth]
        end

        features
      end

      def place_feature(rng, zone, existing, index)
        MAX_ATTEMPTS.times do
          type = weighted_type(rng)
          sizes = SIZE_RANGES.fetch(type)
          width = lerp(sizes[:width][0], sizes[:width][1], rng.rand)
          depth = lerp(sizes[:depth][0], sizes[:depth][1], rng.rand)
          half_w = width * 0.5
          half_d = depth * 0.5
          x_min = zone[:x_min] + half_w
          x_max = zone[:x_max] - half_w
          y_min = zone[:y_min] + half_d
          y_max = zone[:y_max] - half_d
          next if x_max <= x_min || y_max <= y_min

          x = x_min + ((x_max - x_min) * rng.rand)
          y = y_min + ((y_max - y_min) * rng.rand)
          candidate = build_feature(index, type, x, y, width, depth)
          next if overlaps_any?(candidate, existing)

          return candidate
        end
        nil
      end

      def build_feature(index, type, x, y, width, depth)
        impassable = type == "house" || type == "lake"
        {
          id: "terrain-#{index + 1}",
          type: type,
          x: x.round(3),
          y: y.round(3),
          width: width.round(3),
          depth: depth.round(3),
          impassable: impassable,
          blocks_los: type == "house",
          move_cost: type == "difficult" ? 2.0 : 1.0
        }
      end

      def weighted_type(rng)
        total = TYPE_WEIGHTS.sum { |(_, weight)| weight }
        roll = rng.rand(total)
        cursor = 0
        TYPE_WEIGHTS.each do |type, weight|
          cursor += weight
          return type if roll < cursor
        end
        TYPE_WEIGHTS.first.first
      end

      def overlaps_any?(candidate, existing)
        footprint = Geometry::Battlefield.feature_footprint(candidate)
        existing.any? do |other|
          Geometry::Battlefield.rectangles_overlap?(footprint, Geometry::Battlefield.feature_footprint(other))
        end
      end

      def lerp(min, max, t)
        min + ((max - min) * t.to_f)
      end
      private_class_method :place_feature, :build_feature, :weighted_type, :overlaps_any?, :lerp
    end
  end
end
