module Sim
  module Battle
    module State
      module_function

      def create(player_a, player_b, catalog, terrain: [])
        {
          catalog: catalog,
          players: { left: player_a, right: player_b },
          sides: {
            left: build_side(player_a, "left", 0),
            right: build_side(player_b, "right", 1)
          },
          terrain: Array(terrain),
          rounds: []
        }
      end

      def living?(side)
        side[:combatants].any? { |entry| entry[:current_health].to_i > 0 }
      end

      def all_routing?(sides)
        living = sides.flat_map { |side| side[:combatants] }.select { |entry| entry[:current_health].to_i > 0 }
        living.any? && living.all? { |entry| entry[:is_routing] }
      end

      def side_health(side)
        side[:combatants].sum { |entry| entry[:current_health].to_i }
      end

      def apply_faction_passives!(side)
        Rules.for(:round).apply_passives!(side)
      end

      def snapshot_side(player, side, catalog)
        {
          player_id: player[:id],
          player_name: player[:name],
          faction: catalog.faction(player[:faction_id]),
          combatants: side[:combatants].map { |entry| combatant_public(entry) }
        }
      end

      def snapshot_battlefield(sides)
        sides.flat_map { |side| side[:combatants] }
          .select { |entry| entry[:current_health].to_i > 0 }
          .map { |entry| combatant_public(entry).merge(side_key: entry[:side_key]) }
      end

      def snapshot_combatant(combatant)
        {
          entity_id: combatant[:entity_id],
          name: combatant[:name],
          kind: combatant[:kind],
          side_key: combatant[:side_key],
          lane: combatant[:lane],
          row: combatant[:row],
          x: combatant[:x],
          y: combatant[:y],
          facing: combatant[:facing],
          current_health: combatant[:current_health],
          max_health: combatant[:max_health],
          model_health: combatant[:model_health],
          models_remaining: combatant[:models_remaining],
          starting_models: combatant[:starting_models],
          frontage: combatant[:frontage],
          max_files: combatant[:max_files],
          files: combatant[:files],
          ranks: combatant[:ranks],
          base_width: combatant[:base_width],
          base_depth: combatant[:base_depth],
          movement: combatant[:movement],
          morale: combatant[:morale],
          skill: combatant[:skill],
          melee: combatant[:melee],
          ranged: combatant[:ranged],
          spell: combatant[:spell],
          is_routing: combatant[:is_routing],
          armor_type: combatant[:armor_type],
          weapon_type: combatant[:weapon_type],
          attached_heroes: combatant[:attached_heroes] || []
        }
      end

      def sync_battle!(battle)
        sync_side!(battle[:players][:left], battle[:sides][:left])
        sync_side!(battle[:players][:right], battle[:sides][:right])
      end

      def sync_combatant_footprint!(combatant)
        models_remaining = if combatant[:current_health].to_i > 0
          [ 1, (combatant[:current_health].to_f / combatant[:model_health]).ceil ].max
        else
          0
        end
        old_half_depth = Geometry::Battlefield.unit_dimensions(combatant)[:half_depth]
        metrics = Geometry::Formation.metrics(
          models_remaining: models_remaining,
          frontage: combatant[:frontage],
          max_files: combatant[:max_files],
          model_width: combatant[:model_width],
          model_depth: combatant[:model_depth]
        )
        combatant[:models_remaining] = models_remaining
        combatant[:files] = metrics[:files]
        combatant[:ranks] = metrics[:ranks]
        combatant[:base_width] = metrics[:footprint_width]
        combatant[:base_depth] = metrics[:footprint_depth]
        # Casualties trim rear ranks: keep the front edge fixed so melee contact
        # does not open a gap that would allow another charge.
        new_half_depth = Geometry::Battlefield.unit_dimensions(combatant)[:half_depth]
        depth_delta = old_half_depth - new_half_depth
        if depth_delta.abs > 0.0001
          forward = Geometry::Battlefield.facing_vector(combatant[:facing])
          combatant[:x] = combatant[:x].to_f + (forward[:x] * depth_delta)
          combatant[:y] = combatant[:y].to_f + (forward[:y] * depth_delta)
        end
        combatant
      end

      def build_side(player, side_key, side_index)
        units_by_id = player[:roster].select { |entry| entry[:kind] == "unit" }.index_by { |entry| entry[:id] }
        heroes_by_host = Hash.new { |hash, key| hash[key] = [] }

        player[:roster]
          .select { |entry| entry[:kind] == "hero" && entry.dig(:state, :current_health).to_i > 0 && entry.dig(:state, :attached_to) }
          .each { |hero| heroes_by_host[hero[:state][:attached_to]] << hero }

        combatants = player[:roster]
          .select { |entry| entry.dig(:state, :current_health).to_i > 0 }
          .reject { |entry| entry[:kind] == "hero" && entry.dig(:state, :attached_to) && units_by_id.key?(entry[:state][:attached_to]) }
          .select { |entry| Entities::Footprint.deployable?(entry) }
          .map { |entity| build_combatant(entity, heroes_by_host[entity[:id]] || [], side_key, side_index) }

        {
          player_id: player[:id],
          player_name: player[:name],
          faction_id: player[:faction_id],
          side_key: side_key,
          combatants: combatants
        }
      end

      def build_combatant(entity, attached_heroes, side_key, side_index)
        abilities = entity.dig(:components, :abilities).to_a.dup
        combat = entity[:components][:combat]
        melee_contributors = [ contributor_from(entity, combat[:melee]) ]
        ranged_contributors = []
        melee = combat[:melee]
        ranged = combat[:ranged]
        spell = combat[:spell]
        weapon_type = combat[:weapon_type]

        if ranged.positive? || spell.positive?
          ranged_contributors << missile_contributor_from(entity)
        end

        attached_heroes.each do |hero|
          hero_combat = hero[:components][:combat]
          melee += hero_combat[:melee]
          ranged += hero_combat[:ranged]
          spell += hero_combat[:spell]
          melee_contributors << contributor_from(hero, hero_combat[:melee]).merge(attached_slot: hero[:state][:attached_slot])
          if hero_combat[:ranged].positive? || hero_combat[:spell].positive?
            ranged_contributors << missile_contributor_from(hero, attached_slot: hero[:state][:attached_slot])
          end
          abilities.concat(hero.dig(:components, :abilities).to_a)
          weapon_type = "magic" if hero_combat[:spell] > spell
        end

        ability_set = abilities.uniq
        host_ctx = {
          ability_set: ability_set,
          melee: melee,
          melee_contributors: melee_contributors
        }
        Rules.for(:setup).apply_attach!(host_ctx)
        melee = host_ctx[:melee]

        projected = Geometry::Battlefield.battle_position(
          {
            x: entity.dig(:components, :formation, :x),
            y: entity.dig(:components, :formation, :y),
            facing: entity.dig(:components, :formation, :facing)
          },
          side_index
        )

        sync_combatant_footprint!(
          {
            entity_id: entity[:id],
            name: entity[:name],
            kind: entity[:kind],
            side_key: side_key,
            side_index: side_index,
            lane: entity.dig(:components, :formation, :lane),
            row: entity.dig(:components, :formation, :row),
            x: projected[:x],
            y: projected[:y],
            facing: projected[:facing],
            frontage: entity.dig(:components, :formation, :frontage),
            max_files: entity.dig(:components, :formation, :max_files),
            files: entity.dig(:components, :formation, :files),
            ranks: entity.dig(:components, :formation, :ranks),
            base_width: entity.dig(:components, :formation, :width),
            base_depth: entity.dig(:components, :formation, :depth),
            model_class: entity.dig(:components, :formation, :model_class),
            model_width: entity.dig(:components, :formation, :model_width),
            model_depth: entity.dig(:components, :formation, :model_depth),
            movement: combat[:movement],
            morale: combat[:morale],
            skill: combat[:skill],
            shooting_range: combat[:shooting_range],
            spell_range: combat[:spell_range],
            shooting_template: combat[:shooting_template],
            spell_template: combat[:spell_template],
            requires_line_of_sight: combat[:requires_line_of_sight],
            armor_type: combat[:armor_type],
            weapon_type: weapon_type,
            melee: melee,
            ranged: ranged,
            spell: spell,
            initiative: combat[:initiative],
            current_health: entity[:state][:current_health],
            max_health: entity.dig(:components, :health, :max),
            model_health: entity.dig(:components, :health, :model_health),
            starting_models: [ 1, (entity[:state][:current_health].to_f / entity.dig(:components, :health, :model_health)).ceil ].max,
            is_routing: !!entity[:state][:is_routing],
            attached_heroes: attached_heroes.map do |hero|
              {
                entity_id: hero[:id],
                name: hero[:name],
                slot: hero[:state][:attached_slot],
                morale: hero.dig(:components, :combat, :morale),
                skill: hero.dig(:components, :combat, :skill),
                abilities: hero.dig(:components, :abilities).to_a
              }
            end,
            abilities: ability_set,
            contributors: { melee: melee_contributors, ranged: ranged_contributors },
            attacks: combat[:attacks],
            missile_attacks: combat[:missile_attacks] || 1
          }
        )
      end

      def contributor_from(entity, power)
        {
          entity_id: entity[:id],
          name: entity[:name],
          kind: entity[:kind],
          power: power,
          skill: entity.dig(:components, :combat, :skill),
          weapon_type: entity.dig(:components, :combat, :weapon_type),
          abilities: entity.dig(:components, :abilities).to_a.dup,
          experience_gain: 0
        }
      end

      def missile_contributor_from(entity, attached_slot: nil)
        combat = entity[:components][:combat]
        ranged = combat[:ranged].to_i
        spell = combat[:spell].to_i
        contributor_from(entity, [ ranged, spell ].max).merge(
          ranged: ranged,
          spell: spell,
          shooting_range: combat[:shooting_range],
          spell_range: combat[:spell_range],
          shooting_template: combat[:shooting_template],
          spell_template: combat[:spell_template],
          requires_line_of_sight: combat[:requires_line_of_sight],
          missile_attacks: combat[:missile_attacks] || 1,
          initiative: combat[:initiative],
          attached_slot: attached_slot
        )
      end

      def sync_side!(player, side)
        side[:combatants].each do |combatant|
          entity = player[:roster].find { |entry| entry[:id] == combatant[:entity_id] }
          next unless entity

          entity[:state][:current_health] = combatant[:current_health]
          entity[:state][:is_routing] = combatant[:is_routing]
          formation = entity[:components][:formation]
          formation[:files] = combatant[:files]
          formation[:ranks] = combatant[:ranks]
          formation[:row] = combatant[:row]
          formation[:lane] = combatant[:lane]
          formation[:x] = combatant[:x]
          formation[:y] = combatant[:y]
          formation[:facing] = combatant[:facing]
          formation[:width] = combatant[:base_width]
          formation[:depth] = combatant[:base_depth]
        end

        side[:combatants].each do |combatant|
          (combatant[:contributors][:melee] + combatant[:contributors][:ranged]).each do |entry|
            next unless entry[:kind] == "hero" && entry[:experience_gain].to_i.positive?

            hero = player[:roster].find { |candidate| candidate[:id] == entry[:entity_id] }
            next unless hero

            hero[:components][:progression][:experience] += entry[:experience_gain]
          end
        end

        player[:roster].each do |entity|
          next unless entity[:kind] == "unit"

          entity[:state][:attached_hero_ids] = Array(entity[:state][:attached_hero_ids]).select do |hero_id|
            hero = player[:roster].find { |candidate| candidate[:id] == hero_id }
            hero && hero.dig(:state, :current_health).to_i > 0
          end
        end
      end

      def combatant_public(entry)
        {
          entity_id: entry[:entity_id],
          name: entry[:name],
          kind: entry[:kind],
          lane: entry[:lane],
          row: entry[:row],
          current_health: entry[:current_health],
          max_health: entry[:max_health],
          models_remaining: entry[:models_remaining],
          x: entry[:x],
          y: entry[:y],
          facing: entry[:facing],
          frontage: entry[:frontage],
          max_files: entry[:max_files],
          files: entry[:files],
          ranks: entry[:ranks],
          base_width: entry[:base_width],
          base_depth: entry[:base_depth],
          model_class: entry[:model_class],
          model_width: entry[:model_width],
          model_depth: entry[:model_depth],
          movement: entry[:movement],
          morale: entry[:morale],
          skill: entry[:skill],
          shooting_range: entry[:shooting_range],
          spell_range: entry[:spell_range],
          shooting_template: entry[:shooting_template],
          spell_template: entry[:spell_template],
          requires_line_of_sight: entry[:requires_line_of_sight],
          is_routing: entry[:is_routing],
          attached_heroes: entry[:attached_heroes] || []
        }
      end
    end
  end
end
