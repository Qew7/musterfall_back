module Sim
  module Battle
    module SpellWorld
      TERRAIN_DEFAULTS = {
        "forest" => { width: 4.0, depth: 3.0, impassable: false, blocks_los: false, move_cost: 1.0 },
        "difficult" => { width: 3.0, depth: 3.0, impassable: false, blocks_los: false, move_cost: 2.0 },
        "mist" => { width: 4.0, depth: 3.0, impassable: false, blocks_los: true, move_cost: 1.0 },
        "fire" => { width: 5.0, depth: 1.0, impassable: false, blocks_los: false, move_cost: 2.0, entry_damage: 1 },
        "corpse_mire" => {
          width: 3.0, depth: 3.0, impassable: false, blocks_los: false, move_cost: 1.0,
          entry_damage: 2, damage_type: "magic", rule_key: "corpseTrail"
        }
      }.freeze

      BOARD_SPAN = Math.hypot(
        Geometry::Battlefield::CONFIG[:width].to_f,
        Geometry::Battlefield::CONFIG[:height].to_f
      ).freeze

      SUMMONS = {
        "phoenix" => { name: "Феникс", health: 7, models: 1, melee: 6, movement: 8, armor_type: "light", weapon_type: "fire", abilities: %w[flying fear] },
        "fey" => { name: "Феи", health: 4, models: 4, melee: 4, movement: 6, armor_type: "light", weapon_type: "puncture", abilities: %w[skirmisher] },
        "great_beast" => { name: "Великий зверь", health: 8, models: 1, melee: 7, movement: 7, armor_type: "medium", weapon_type: "blunt", abilities: %w[monster fear] },
        "spectral_hounds" => { name: "Призрачные псы", health: 6, models: 3, melee: 4, movement: 7, armor_type: "light", weapon_type: "puncture", abilities: %w[skirmisher] },
        "zombies" => { name: "Поднятые мертвецы", health: 5, models: 5, melee: 2, movement: 3, armor_type: "light", weapon_type: "blunt", abilities: %w[undead resolute] },
        "skeletons" => { name: "Призванные скелеты", health: 6, models: 6, melee: 3, movement: 4, armor_type: "light", weapon_type: "slash", abilities: %w[undead resolute] },
        "revenants" => { name: "Ревенанты", health: 6, models: 3, melee: 5, movement: 5, armor_type: "medium", weapon_type: "slash", abilities: %w[undead fear] },
        "goblins" => { name: "Туннельные гоблины", health: 5, models: 5, melee: 3, movement: 5, armor_type: "light", weapon_type: "puncture", abilities: %w[skirmisher] },
        "rift_mutant" => { name: "Мутант разлома", health: 8, models: 1, melee: 6, movement: 5, armor_type: "magic", weapon_type: "blunt", abilities: %w[monster fear] }
      }.freeze

      module_function

      def add_terrain!(terrain, type:, x:, y:, all_combatants:, allow_occupied: false, **overrides)
        defaults = TERRAIN_DEFAULTS.fetch(type.to_s, TERRAIN_DEFAULTS.fetch("difficult"))
        feature = defaults.merge(
          id: next_terrain_id(terrain),
          type: type.to_s,
          x: x.to_f.round(3),
          y: y.to_f.round(3)
        ).merge(overrides)
        return nil unless feature_clear?(feature, terrain, allow_occupied ? [] : all_combatants)

        terrain << feature
        feature
      end

      def remove_terrain!(terrain, feature)
        terrain.delete(feature)
        feature
      end

      def expire_terrain!(terrain, moment:, side_key:)
        removed = Array(terrain).select do |feature|
          expiry = feature[:spell_expires] || {}
          next false unless expiry[:side_key].to_s == side_key.to_s

          if expiry[:moment].to_s == "turns" && moment.to_sym == :end_turn
            expiry[:remaining_turns] = expiry[:remaining_turns].to_i - 1
            expiry[:remaining_turns] <= 0
          else
            expiry[:moment].to_s == moment.to_s
          end
        end
        terrain.reject! { |feature| removed.include?(feature) }
        removed
      end

      def random_free_pose(rng, unit:, all_combatants:, terrain:, center:, radius: 8.0, expand: false)
        obstacles = Pathing::Obstacles.around(unit, units: all_combatants, terrain: terrain)
        found = search_free_pose(rng, unit, obstacles, center, radius.to_f)
        return found if found || !expand

        search_free_pose(rng, unit, obstacles, center, BOARD_SPAN, start_radius: radius.to_f)
      end

      def pose_clear?(unit, all_combatants, terrain)
        inside_battlefield?(unit) &&
          Pathing::Obstacles.around(unit, units: all_combatants, terrain: terrain).clear?(unit)
      end

      def nearest_clear_facing(unit, desired, obstacles, contact_id = nil)
        return desired if obstacles.clear?(unit.merge(facing: desired), contact_id: contact_id)

        best = nil
        best_gap = Float::INFINITY
        (1..18).each do |step|
          offset = step * 10.0
          [ offset, -offset ].each do |delta|
            gap = delta.abs
            next if gap >= best_gap

            facing = Geometry::Battlefield.normalize_facing(desired + delta)
            next unless obstacles.clear?(unit.merge(facing: facing), contact_id: contact_id)

            best = facing
            best_gap = gap
          end
        end
        best
      end

      def face_nearest_enemy!(unit, enemies:, all_combatants:, terrain:)
        living = Array(enemies).select { |entry| entry[:current_health].to_f > 0 && !entry[:x].nil? }
        enemy = living.min_by { |entry| Geometry::Battlefield.distance_between_units(unit, entry) }
        return unit unless enemy

        desired = Geometry::Battlefield.heading_to(unit, enemy)
        obstacles = Pathing::Obstacles.around(unit, units: all_combatants, terrain: terrain)
        facing = nearest_clear_facing(unit, desired, obstacles, unit[:entity_id])
        unit[:facing] = facing if facing
        unit
      end

      # After facing / footprint sync a spawn can sit inside another tray. Relocate
      # or report failure so the caller can drop the summon instead of leaving a clip.
      def nudge_to_clear_pose!(unit, rng:, all_combatants:, terrain:, radius: 12.0)
        return true if pose_clear?(unit, all_combatants, terrain)

        pose = random_free_pose(
          rng, unit: unit, all_combatants: all_combatants, terrain: terrain, center: unit, radius: radius, expand: true
        )
        return false unless pose

        unit[:x] = pose[:x]
        unit[:y] = pose[:y]
        unit[:facing] = pose[:facing]
        true
      end

      def summon!(side:, kind:, pose:, expires: :battle, all_combatants: nil)
        profile = SUMMONS.fetch(kind.to_s)
        id = next_summon_id(side)
        health = profile.fetch(:health)
        models = profile.fetch(:models)
        model_health = (health.to_f / models).ceil
        combatant = {
          entity_id: id,
          name: profile[:name],
          kind: "unit",
          side_key: side[:side_key],
          side_index: side[:side_key].to_s == "left" ? 0 : 1,
          lane: "center",
          row: "front",
          x: pose[:x],
          y: pose[:y],
          facing: pose[:facing],
          movement: profile[:movement],
          morale: 10,
          skill: 4,
          armor_type: profile[:armor_type],
          weapon_type: profile[:weapon_type],
          melee: profile[:melee],
          ranged: 0,
          spell: 0,
          initiative: 4,
          current_health: health,
          max_health: health,
          model_health: model_health,
          starting_models: models,
          models_remaining: models,
          is_routing: false,
          attached_heroes: [],
          abilities: profile[:abilities],
          contributors: {
            melee: [ { entity_id: id, name: profile[:name], kind: "unit", power: profile[:melee], skill: 4, weapon_type: profile[:weapon_type], abilities: profile[:abilities], experience_gain: 0 } ],
            ranged: []
          },
          attacks: 1,
          missile_attacks: 1,
          summoned: true,
          summon_kind: kind.to_s,
          summon_expires: expires
        }.merge(summon_footprint(kind))
        side[:combatants] << combatant
        combatant
      end

      def clone_combatant!(side:, source:, pose:, remaining_turns:, all_combatants: nil)
        copy = Marshal.load(Marshal.dump(source))
        id = next_summon_id(side)
        copy[:entity_id] = id
        copy[:name] = "Двойник (#{source[:name]})"
        copy[:x] = pose[:x]
        copy[:y] = pose[:y]
        copy[:facing] = pose[:facing]
        copy[:summoned] = true
        copy[:summon_kind] = "doppelganger"
        copy[:summon_remaining_turns] = remaining_turns.to_i
        copy[:spell_effects] = []
        copy[:is_routing] = false
        Array(copy[:attached_heroes]).each { |hero| hero[:entity_id] = "#{id}-#{hero[:entity_id]}" }
        %i[melee ranged].each do |role|
          Array(copy.dig(:contributors, role)).each do |contributor|
            contributor[:entity_id] = "#{id}-#{contributor[:entity_id]}"
            contributor[:experience_gain] = 0
          end
        end
        side[:combatants] << copy
        copy
      end

      def contact_pose(unit, target, vector: :rear)
        offset_facing = case vector.to_sym
        when :rear then target[:facing].to_f + 180
        when :left then target[:facing].to_f - 90
        when :right then target[:facing].to_f + 90
        else target[:facing].to_f
        end
        direction = Geometry::Battlefield.facing_vector(offset_facing)
        origin = unit.merge(
          x: target[:x].to_f + (direction[:x] * 6.0),
          y: target[:y].to_f + (direction[:y] * 6.0)
        )
        facing = Geometry::Battlefield.heading_to(origin, target)
        Geometry::Battlefield.charge_destination(origin, target, facing)
      end

      def inside_battlefield?(pose)
        Geometry::Battlefield.unit_corners(pose).all? do |point|
          point[:x].between?(0, Geometry::Battlefield::CONFIG[:width]) &&
            point[:y].between?(0, Geometry::Battlefield::CONFIG[:height])
        end
      end

      def feature_clear?(feature, terrain, combatants)
        footprint = Geometry::Battlefield.feature_footprint(feature)
        inside_battlefield?(footprint) &&
          Array(terrain).none? { |other| Geometry::Battlefield.rectangles_overlap?(footprint, Geometry::Battlefield.feature_footprint(other)) } &&
          Array(combatants).none? { |unit| unit[:current_health].to_f > 0 && Geometry::Battlefield.rectangles_overlap?(footprint, unit) }
      end

      # One immutable obstacle snapshot per search; subsequent summons rebuild it.
      def search_free_pose(rng, unit, obstacles, center, radius, start_radius: nil)
        cx = center[:x].to_f
        cy = center[:y].to_f
        try = lambda do |x, y, facing|
          candidate = unit.merge(x: x, y: y, facing: facing)
          candidate if obstacles.clear?(candidate)
        end
        unless start_radius
          30.times do
            angle = rng.rand * Math::PI * 2
            distance = rng.rand * radius
            found = try.call(cx + (Math.cos(angle) * distance), cy + (Math.sin(angle) * distance), rng.rand(4) * 90.0)
            return found if found
          end
        end
        # Constant arc spacing avoids widening blind spots on distant rings.
        first_ring = start_radius ? start_radius + 1.0 : 0.0
        rings = first_ring.step(radius, 1.0).to_a
        rings << radius if rings.last != radius && first_ring <= radius
        facings = [ unit[:facing].to_f, 0.0, 90.0, 45.0, 135.0 ].uniq
        rings.each do |ring|
          samples = [ 8, (2 * Math::PI * ring).ceil ].max
          samples.times do |index|
            angle = index * Math::PI * 2 / samples
            x = cx + Math.cos(angle) * ring
            y = cy + Math.sin(angle) * ring
            next unless x.between?(0, Geometry::Battlefield::CONFIG[:width]) &&
              y.between?(0, Geometry::Battlefield::CONFIG[:height])

            facings.each do |facing|
              found = try.call(x, y, facing)
              return found if found
            end
          end
        end
        nil
      end
      private_class_method :search_free_pose

      def summon_footprint(kind)
        models = SUMMONS.fetch(kind.to_s).fetch(:models)
        files = [ models, 3 ].min
        ranks = (models.to_f / files).ceil
        {
          frontage: files, max_files: 3, files: files, ranks: ranks,
          base_width: files.to_f, base_depth: ranks.to_f,
          model_class: "infantry", model_width: 1.0, model_depth: 1.0
        }
      end

      def summon_prototype(kind, pose:)
        summon_footprint(kind).merge(
          x: pose[:x], y: pose[:y], facing: pose[:facing].to_f,
          current_health: SUMMONS.fetch(kind.to_s).fetch(:health)
        )
      end

      def next_terrain_id(terrain)
        sequence = Array(terrain).filter_map { |entry| entry[:id].to_s[/\d+\z/].to_i }.max.to_i + 1
        "terrain-#{sequence}"
      end
      private_class_method :next_terrain_id

      def next_summon_id(side)
        # Battle-local state, independent of wall clock and surviving combatants.
        side[:summon_sequence] = side.fetch(:summon_sequence, 0) + 1
        "summon-#{side.fetch(:side_key)}-#{side[:summon_sequence]}"
      end
      private_class_method :next_summon_id
    end
  end
end
