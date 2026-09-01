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

      def random_free_pose(rng, unit:, all_combatants:, terrain:, center:, radius: 8.0)
        cx = center[:x].to_f
        cy = center[:y].to_f
        try = lambda do |x, y, facing|
          candidate = unit.merge(x: x, y: y, facing: facing)
          return nil unless inside_battlefield?(candidate)

          obstacles = Pathing::Obstacles.around(candidate, units: all_combatants, terrain: terrain)
          candidate if obstacles.clear?(candidate)
        end
        30.times do
          angle = rng.rand * Math::PI * 2
          distance = rng.rand * radius.to_f
          found = try.call(cx + (Math.cos(angle) * distance), cy + (Math.sin(angle) * distance), rng.rand(4) * 90.0)
          return found if found
        end
        [ 2.5, 4.0, 5.5, 7.0, radius.to_f ].uniq.each do |ring|
          8.times do |index|
            angle = index * Math::PI / 4.0
            found = try.call(cx + (Math.cos(angle) * ring), cy + (Math.sin(angle) * ring), unit[:facing].to_f)
            return found if found
          end
        end
        nil
      end

      def summon!(side:, kind:, pose:, expires: :battle)
        profile = SUMMONS.fetch(kind.to_s)
        id = next_summon_id(side)
        health = profile.fetch(:health)
        models = profile.fetch(:models)
        model_health = (health.to_f / models).ceil
        files = [ models, 3 ].min
        ranks = (models.to_f / files).ceil
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
          frontage: files,
          max_files: 3,
          files: files,
          ranks: ranks,
          base_width: files.to_f,
          base_depth: ranks.to_f,
          model_class: "infantry",
          model_width: 1.0,
          model_depth: 1.0,
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
        }
        side[:combatants] << combatant
        combatant
      end

      def clone_combatant!(side:, source:, pose:, remaining_turns:)
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
          Array(combatants).none? { |unit| unit[:current_health].to_i > 0 && Geometry::Battlefield.rectangles_overlap?(footprint, unit) }
      end

      def next_terrain_id(terrain)
        sequence = Array(terrain).filter_map { |entry| entry[:id].to_s[/\d+\z/].to_i }.max.to_i + 1
        "terrain-#{sequence}"
      end
      private_class_method :next_terrain_id

      def next_summon_id(side)
        "summon-#{side[:side_key]}-#{Array(side[:combatants]).count { |entry| entry[:summoned] } + 1}"
      end
      private_class_method :next_summon_id
    end
  end
end
