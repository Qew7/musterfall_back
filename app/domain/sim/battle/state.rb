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

      def standing_cost(side)
        Array(side[:combatants]).sum { |entry| fighting?(entry) ? entry[:cost].to_i : 0 }
      end

      # VP the opponent scores from this side's casualties.
      def victory_points(side)
        Array(side[:combatants]).sum { |entry| unit_bounty(entry) }
      end

      def victory_score(own_side, enemy_side)
        [ victory_points(enemy_side), standing_cost(own_side) ]
      end

      def unit_bounty(unit)
        cost = unit[:cost].to_i
        return 0 if cost <= 0

        starting = [ unit[:starting_models].to_i, 1 ].max
        remaining = fighting?(unit) ? unit[:models_remaining].to_i : 0
        return cost if remaining <= 0
        return cost / 2 if remaining * 2 <= starting

        0
      end

      def fighting?(unit)
        unit[:current_health].to_i > 0 && !unit[:is_routing]
      end

      def apply_faction_passives!(side, terrain: [], rng: nil)
        Rules.for(:round).apply_passives!(side.merge(terrain: Array(terrain), rng: rng))
      end

      def resolve_summons_end_round!(side)
        events = []
        side[:combatants].each do |combatant|
          next unless combatant[:summoned] && combatant[:current_health].to_i > 0
          next unless combatant[:summon_kind] == "rift_mutant"

          combatant[:current_health] -= 1
          sync_combatant_footprint!(combatant)
          events << "#{combatant[:name]} теряет 1 здоровье из-за нестабильной мутации."
        end
        side[:combatants].reject! do |combatant|
          combatant[:summoned] && (combatant[:current_health].to_i <= 0 || combatant[:summon_expires] == :round)
        end
        events
      end

      def tick_summons!(sides)
        vanished = []
        Array(sides).each do |side|
          side[:combatants].reject! do |combatant|
            next false unless combatant[:summoned] && combatant[:summon_remaining_turns]

            combatant[:summon_remaining_turns] -= 1
            next false if combatant[:summon_remaining_turns].positive?

            vanished << combatant
            true
          end
        end
        vanished
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
          cost: combatant[:cost],
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
          magic_school: combatant[:magic_school],
          spell_keys: Array(combatant[:spell_keys]),
          is_routing: combatant[:is_routing],
          armor_type: combatant[:armor_type],
          weapon_type: combatant[:weapon_type],
          attached_heroes: combatant[:attached_heroes] || [],
          spell_effects: SpellEffects.public_for(combatant),
          summoned: !!combatant[:summoned],
          summon_kind: combatant[:summon_kind]
        }
      end

      def sync_battle!(battle)
        sync_side!(battle[:players][:left], battle[:sides][:left])
        sync_side!(battle[:players][:right], battle[:sides][:right])
      end

      def sync_combatant_footprint!(combatant)
        models_remaining = combatant_models_remaining(combatant)
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
            cost: entity.dig(:components, :economy, :cost).to_i + attached_heroes.sum { |hero| hero.dig(:components, :economy, :cost).to_i },
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
            magic_school: ranged_contributors.filter_map { |entry| entry[:magic_school] }.first,
            spell_keys: ranged_contributors.flat_map { |entry| Array(entry[:spell_keys]) }.uniq,
            initiative: combat[:initiative],
            current_health: entity[:state][:current_health],
            max_health: entity.dig(:components, :health, :max),
            model_health: entity.dig(:components, :health, :model_health),
            formation_models: entity.dig(:components, :formation, :models).to_i,
            starting_models: Entities::Footprint.formation_models_remaining(entity),
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

      def combatant_models_remaining(combatant)
        return 0 if combatant[:current_health].to_i <= 0
        if combatant[:kind] == "hero"
          models = combatant[:formation_models].to_i
          return models if models.positive?

          return 1
        end
        return 1 if combatant[:model_class].to_s == "machine"

        [ 1, (combatant[:current_health].to_f / combatant[:model_health]).ceil ].max
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
        magic = entity.dig(:components, :hero) || {}
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
          attached_slot: attached_slot,
          magic_school: magic[:magic_school],
          spell_keys: Array(magic[:spell_keys])
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
          starting_models: entry[:starting_models],
          cost: entry[:cost],
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
          magic_school: entry[:magic_school],
          spell_keys: Array(entry[:spell_keys]),
          requires_line_of_sight: entry[:requires_line_of_sight],
          is_routing: entry[:is_routing],
          attached_heroes: entry[:attached_heroes] || [],
          spell_effects: SpellEffects.public_for(entry),
          summoned: !!entry[:summoned],
          summon_kind: entry[:summon_kind]
        }
      end
    end
  end
end
