module Sim
  module Geometry
    module Battlefield
      # In-place 90° turn: the old flank becomes the new front.
      # Center stays put, width/depth and files/ranks swap, cost is half of base MV.
      # Remaining MV may be spent marching along the new facing. This is not a wheel:
      # a wheel pivots on a front corner and swings the tray through the old front arc.
      module Turn
        FOOTPRINT_KEYS = %i[base_width base_depth files ranks frontage].freeze
        TURN_DEGREES = 90.0
        TURN_ALIGN_DEGREES = 20.0

        def turn_cost(unit)
          [ unit[:movement].to_f / 2.0, 0.0 ].max
        end

        def swapped_footprint(unit)
          files = unit[:files].to_i
          ranks = unit[:ranks].to_i
          {
            base_width: unit[:base_depth].to_f,
            base_depth: unit[:base_width].to_f,
            files: ranks,
            ranks: files,
            frontage: ranks.positive? ? ranks : unit[:frontage]
          }
        end

        def merge_footprint(unit, pose)
          extra = FOOTPRINT_KEYS.each_with_object({}) do |key, hash|
            hash[key] = pose[key] if pose.key?(key) && !pose[key].nil?
          end
          unit.merge(x: pose[:x], y: pose[:y], facing: pose[:facing]).merge(extra)
        end

        def apply_footprint!(unit, pose)
          FOOTPRINT_KEYS.each do |key|
            unit[key] = pose[key] if pose.key?(key) && !pose[key].nil?
          end
          unit
        end

        def footprint_destination(pose)
          dest = { x: pose[:x], y: pose[:y], facing: pose[:facing] }
          FOOTPRINT_KEYS.each do |key|
            dest[key] = pose[key] if pose.key?(key)
          end
          dest
        end

        # Rotate ±90° about the center and swap the tray so the chosen flank is the new front.
        def turn_pose(unit, delta)
          return unit.merge(facing: normalize_facing(unit[:facing])) if delta.abs < 0.0001

          snapped = delta.positive? ? TURN_DEGREES : -TURN_DEGREES
          clamp_battlefield_position(
            x: unit[:x],
            y: unit[:y],
            facing: normalize_facing(unit[:facing].to_f + snapped)
          ).merge(swapped_footprint(unit))
        end

        def apply_turn(unit, to_facing, movement_budget)
          budget = [ movement_budget.to_f, 0.0 ].max
          from_facing = normalize_facing(unit[:facing])
          desired = normalize_facing(to_facing)
          delta = shortest_facing_delta(from_facing, desired)
          idle = merge_footprint(unit, unit).merge(
            facing: from_facing,
            cost: 0.0,
            remaining: budget,
            completed: delta.abs < 0.0001,
            delta: 0.0,
            kind: :turn
          )
          return idle if delta.abs < 0.0001
          return idle.merge(completed: false) unless turn_delta?(delta)

          turn_delta = delta.positive? ? TURN_DEGREES : -TURN_DEGREES
          cost = turn_cost(unit)
          return idle.merge(completed: false) if cost > budget + 0.0001

          pose = turn_pose(unit, turn_delta)
          pose.merge(
            cost: cost,
            remaining: [ budget - cost, 0.0 ].max,
            completed: true,
            delta: turn_delta,
            kind: :turn
          )
        end

        def turn_delta?(delta)
          (delta.abs - TURN_DEGREES).abs <= TURN_ALIGN_DEGREES
        end
      end
    end
  end
end
