module Sim
  module Battle
    class SpellContext
      attr_reader :caster, :host, :acting_side, :target_side, :terrain, :rng, :round_number, :spell

      def initialize(caster:, host:, acting_side:, target_side:, terrain:, rng:, round_number:, spell:)
        @caster = caster
        @host = host
        @acting_side = acting_side
        @target_side = target_side
        @terrain = terrain
        @rng = rng
        @round_number = round_number
        @spell = spell
        @damage = 0
        @affected_ids = []
        @effect_log = []
        @terrain_delta = []
        @summon_ids = []
      end

      def allies
        living(acting_side[:combatants])
      end

      def enemies
        living(target_side[:combatants])
      end

      def all_combatants
        allies + enemies
      end

      def legal_targets(type, requires_los: false)
        targets = case type.to_sym
        when :enemy_unit
          enemies
        when :ally_unit
          allies
        when :damaged_ally_unit
          allies.select { |entry| entry[:current_health].to_i < entry[:max_health].to_i }
        when :enemy_caster
          enemies.select { |entry| caster?(entry) }
        when :caster, :battlefield
          [ host ]
        when :battlefield_point
          point_targets
        else
          []
        end
        targets = targets.select { |target| in_spell_range?(target) }
        requires_los ? targets.select { |target| visible?(target) } : targets
      end

      def score(profile, target, spell:)
        health = target[:current_health].to_i
        missing_health = [ target[:max_health].to_i - health, 0 ].max
        nearby_enemies = enemies.count { |entry| distance(target, entry) <= 4.0 }
        nearby_allies = allies.count { |entry| distance(target, entry) <= 4.0 }
        enemy = nearest(target, enemies)
        gap = enemy ? distance(target, enemy) : 40.0
        close = (24.0 - gap).clamp(-12.0, 24.0)
        dup = duplicate_effect_penalty(target, spell)

        case profile.to_sym
        when :healing, :resurrection
          missing_health * 10
        when :area_healing
          nearby_allies * 10 + missing_health
        when :area_damage, :line_damage, :chain_damage, :delayed_area_damage, :area_damage_over_time
          nearby_enemies * 10 + health
        when :summon, :terrain_block, :area_control, :global_ranged_control
          nearby_enemies * 5 + distance(host, target)
        when :mobility, :ally_aura_mobility
          gap
        when :defensive_buff, :armor_buff, :magic_defense, :ranged_defense, :morale_buff
          missing_health + close + nearby_enemies * 8 + dup
        when :melee_buff, :offense_buff, :charge_buff, :risky_offense_buff
          power = target[:melee].to_f
          models = [ target[:models_remaining].to_i, 1 ].max
          close * 1.5 + power * [ models, 10 ].min * 0.5 + nearby_enemies * 10 + health * 0.1 + dup
        when :accuracy_buff
          close + target[:ranged].to_f * 8 + nearby_enemies * 5 + dup
        when :direct_damage, :armor_piercing_damage, :life_drain, :caster_damage, :damage_over_time, :damage_debuff
          health + (12.0 - distance(host, target)).clamp(-6.0, 12.0) + (health <= 3 ? 12 : 0) + spell.casting_value.to_i * 0.5
        when :movement_debuff, :accuracy_debuff, :area_attack_debuff, :enemy_aura_debuff, :movement_hex
          target[:movement].to_f * 3 + nearby_allies * 8 + health * 0.2
        else
          health + spell.casting_value.to_i
        end
      end

      def visible?(target)
        Geometry::Battlefield.line_of_sight_blockers(caster, target, all_combatants, terrain: terrain).empty?
      end

      def damage!(target, power: nil, amount: nil, type: "magic", hits: 1, area: nil, heal_caster: 0)
        power ||= amount
        total = 0
        effect_targets(target, area, enemies).each do |victim|
          [ hits.to_i, 1 ].max.times do
            break if victim[:current_health].to_i <= 0

            profile = caster.merge(spell: power.to_i, weapon_type: type.to_s)
            vector = Geometry::Battlefield.classify_attack_vector(caster, victim)
            dealt = Phases::AttackResolution.damage(
              profile,
              victim,
              "magic",
              vector,
              round_number,
              weapon_type: type.to_s
            )
            dealt = [ dealt, victim[:current_health].to_i ].min
            victim[:current_health] -= dealt
            State.sync_combatant_footprint!(victim)
            total += dealt
          end
          affect!(victim)
          @effect_log << { kind: "damage", target_id: victim[:entity_id], damage_type: type.to_s, amount: total, hits: hits.to_i }
        end
        heal!(host, amount: heal_caster) if heal_caster.to_i.positive?
        @damage += total
        total
      end

      def heal!(target, amount:, area: nil)
        effect_targets(target, area, allies).sum do |recipient|
          before = recipient[:current_health].to_i
          recipient[:current_health] = [ before + amount.to_i, recipient[:max_health].to_i ].min
          State.sync_combatant_footprint!(recipient)
          healed = recipient[:current_health] - before
          affect!(recipient)
          @effect_log << { kind: "heal", target_id: recipient[:entity_id], amount: healed }
          healed
        end
      end

      def add_effect!(target, modifiers: nil, statuses: nil, triggers: nil, duration: :next_caster_turn, key: spell.key, value: nil, area: nil)
        return schedule_comet!(target, value) if key.to_sym == :comet

        area = :global if key.to_sym == :howling_gale
        effect_targets(target, area, effect_side(key)).map do |recipient|
          effect = SpellEffects.add!(
            recipient,
            key: key,
            modifiers: modifiers || effect_modifiers(key, value),
            statuses: statuses || effect_statuses(key),
            triggers: triggers || effect_triggers(key, value),
            expires: expiry_for(recipient, duration)
          )
          affect!(recipient)
          @effect_log << { kind: "effect", target_id: recipient[:entity_id], effect: effect }
          effect
        end
      end

      def rotate!(target, facing: nil, toward: nil, random: false)
        before = target[:facing].to_f
        desired = if random
          rng.rand(4) * 90.0
        elsif toward
          Geometry::Battlefield.heading_to(target, toward)
        else
          facing.to_f
        end
        target[:facing] = Geometry::Battlefield.normalize_facing(desired)
        affect!(target)
        @effect_log << { kind: "rotate", target_id: target[:entity_id], from: before, to: target[:facing] }
        target
      end

      def teleport!(target, destination: nil, to: nil, center: nil, radius: 8.0)
        destination ||= to
        pose = if destination
          clip_spell_pose(target, target.merge(destination))
        else
          SpellWorld.random_free_pose(
            rng,
            unit: target,
            all_combatants: all_combatants,
            terrain: terrain,
            center: center || target,
            radius: radius
          )
        end
        return nil unless pose

        from = target.slice(:x, :y, :facing)
        target[:x] = pose[:x]
        target[:y] = pose[:y]
        target[:facing] = pose[:facing]
        apply_enemy_facing!(target)
        affect!(target)
        @effect_log << { kind: "teleport", target_id: target[:entity_id], from: from, to: target.slice(:x, :y, :facing) }
        target
      end

      def destination_for(target, profile:)
        enemy = nearest(target, enemies)
        center = case profile.to_sym
        when :advance, :aggressive
          enemy || target
        when :flank
          enemy ? flank_point(enemy) : target
        else
          target
        end
        SpellWorld.random_free_pose(
          rng,
          unit: target,
          all_combatants: all_combatants - [ target ],
          terrain: terrain,
          center: center,
          radius: profile.to_sym == :safe ? 4.0 : 7.0
        )
      end

      def move!(target, profile:, distance:, area: nil)
        effect_targets(target, area, allies).each do |recipient|
          enemy = nearest(recipient, enemies)
          next unless enemy

          heading = Geometry::Battlefield.heading_to(recipient, enemy)
          destination = Geometry::Battlefield.move_along_facing(recipient.merge(facing: heading), distance.to_f)
          teleport!(recipient, to: destination.slice(:x, :y, :facing))
        end
      end

      def resurrect!(target, models:)
        heal!(target, amount: models.to_i * [ target[:model_health].to_i, 1 ].max)
      end

      def terrain!(type, at:, duration: :battle)
        terrain_type, overrides = {
          gravity_well: [ "difficult", { name: "Колодец тяжести", move_cost: 3.0 } ],
          thorn_wall: [ "difficult", { name: "Стена шипов", impassable: true } ]
        }.fetch(type.to_sym, [ type.to_s, {} ])
        add_terrain!(type: terrain_type, point: at, duration: duration, **overrides)
      end

      def add_terrain!(type:, point:, duration: :battle, **overrides)
        feature = nil
        terrain_candidate_points(point).each do |x, y|
          feature = TerrainDelta.add!(
            terrain,
            @terrain_delta,
            type: type,
            x: x,
            y: y,
            all_combatants: all_combatants,
            **overrides
          )
          break if feature
        end
        return nil unless feature

        feature[:spell_expires] = expiry_for(host, duration) unless duration == :battle
        feature
      end

      def remove_terrain!(feature)
        TerrainDelta.remove!(terrain, feature, holder: @terrain_delta)
      end

      def summon!(kind = nil, point: nil, near: nil, target: nil, contact: nil, count: nil, expires: :battle, **options)
        kind ||= options.fetch(:kind)
        point ||= near
        prototype = summon_prototype(kind)
        pose = if target && contact
          [ contact.to_sym, :left, :right ].uniq.filter_map do |vector|
            candidate = SpellWorld.contact_pose(prototype, target, vector: vector)
            obstacles = Pathing::Obstacles.around(candidate, units: all_combatants, terrain: terrain)
            candidate if SpellWorld.inside_battlefield?(candidate) && obstacles.clear?(candidate, contact_id: target[:entity_id])
          end.first
        elsif point
          SpellWorld.random_free_pose(rng, unit: prototype, all_combatants: all_combatants, terrain: terrain, center: point, radius: 5.0)
        elsif target
          SpellWorld.random_free_pose(rng, unit: prototype, all_combatants: all_combatants, terrain: terrain, center: target, radius: 6.0)
        end
        return nil unless pose

        apply_enemy_facing!(pose)
        summon = SpellWorld.summon!(side: acting_side, kind: kind, pose: pose, expires: expires)
        summon[:current_health] = [ summon[:current_health], count.to_i ].min if count.to_i.positive?
        record_summon!(summon)
      end

      def clone_unit!(source, remaining_turns: nil)
        remaining_turns ||= rng.rand(3) + 2
        # Drop entity_id so Obstacles.around does not treat the original as "self".
        pose = SpellWorld.random_free_pose(
          rng,
          unit: source.merge(entity_id: nil),
          all_combatants: all_combatants,
          terrain: terrain,
          center: source,
          radius: 8.0
        )
        return nil unless pose

        apply_enemy_facing!(pose)
        summon = SpellWorld.clone_combatant!(
          side: acting_side,
          source: source,
          pose: pose,
          remaining_turns: remaining_turns
        )
        record_summon!(summon, remaining_turns: remaining_turns)
      end

      def nearest(source, entries)
        Array(entries).min_by { |entry| Geometry::Battlefield.distance_between_units(source, entry) }
      end

      def result
        {
          damage: @damage,
          affected_ids: @affected_ids.uniq,
          effects: @effect_log,
          terrain_delta: @terrain_delta,
          summon_ids: @summon_ids
        }
      end

      private

      def clip_spell_pose(unit, desired)
        obstacles = Pathing::Obstacles.around(unit, units: all_combatants, terrain: terrain)
        ok = ->(pose) { spell_pose_viable?(unit, pose, obstacles) }
        return desired if ok.call(desired)

        origin = unit.merge(facing: desired[:facing])
        best = ok.call(origin) ? origin : (ok.call(unit) ? unit : nil)
        lo = 0.0
        hi = 1.0
        12.times do
          mid = (lo + hi) * 0.5
          pose = unit.merge(
            x: unit[:x].to_f + ((desired[:x].to_f - unit[:x].to_f) * mid),
            y: unit[:y].to_f + ((desired[:y].to_f - unit[:y].to_f) * mid),
            facing: desired[:facing]
          )
          if ok.call(pose)
            best = pose
            lo = mid
          else
            hi = mid
          end
        end
        best
      end

      # ponytail: anchors sit on unit centers; wall is 3×3 so exact point is usually occupied.
      # Ring search keeps SpellWorld's clear-footprint rule without silent no-op casts.
      def terrain_candidate_points(point)
        x = point[:x].to_f
        y = point[:y].to_f
        [ [ x, y ] ] + [ 2.5, 3.5, 4.5, 5.5 ].flat_map do |radius|
          8.times.map do |index|
            angle = index * Math::PI / 4.0
            [ x + (Math.cos(angle) * radius), y + (Math.sin(angle) * radius) ]
          end
        end
      end

      def caster?(entry)
        entry[:spell].to_i.positive? ||
          Array(entry.dig(:contributors, :ranged)).any? { |contributor| contributor[:spell].to_i.positive? }
      end

      def in_spell_range?(target)
        return true if target.equal?(host)

        range = spell.respond_to?(:range) ? spell.range : nil
        Decisions::Targeting.in_spell_range?(caster, target, range: range)
      end

      def point_targets
        profile = spell.const_get(:SCORE_PROFILE)
        anchors = profile.to_sym == :area_healing ? allies : enemies
        anchors = [ host ] if anchors.empty?
        anchors.map do |entry|
          {
            entity_id: entry[:entity_id],
            x: entry[:x],
            y: entry[:y],
            facing: entry[:facing],
            base_width: 0.1,
            base_depth: 0.1,
            name: "точку у #{entry[:name]}"
          }
        end
      end

      def effect_targets(target, area, pool)
        entries = Array(pool)
        return entries if area&.to_sym == :global

        case area&.to_sym
        when :burst, :aura
          entries.select { |entry| distance(target, entry) <= 4.0 }
        when :chain
          primary = entries.include?(target) ? target : nearest(target, entries)
          [ primary, *entries.reject { |entry| entry.equal?(primary) }.sort_by { |entry| distance(primary, entry) }.first(2) ].compact
        when :line
          entries.select { |entry| Geometry::Battlefield.distance_point_to_segment(entry, caster, target) <= 1.5 }
        else
          entries.include?(target) ? [ target ] : [ nearest(target, entries) ].compact
        end
      end

      def effect_side(key)
        hostile = %i[
          blinded withering enfeebled entangled ember_cage twist_luck
          gravity_well howling_gale miasma plague primal_roar
        ]
        hostile.include?(key.to_sym) ? enemies : allies
      end

      def effect_modifiers(key, value)
        amount = value.to_f
        {
          blinded: { skill: -amount },
          killing_frenzy: { melee: amount, movement: 1 },
          deathly_vigor: { melee: amount },
          enfeebled: { melee: -amount },
          entangled: { movement: -amount },
          charge_frenzy: { melee: amount, movement: 1 },
          foresight: { skill: amount },
          twist_luck: { skill: -amount },
          gravity_well: { movement: -amount },
          miasma: { movement: -amount },
          oakheart: { armor_factor: 0.7 },
          primal_roar: { morale: -amount },
          wild_fury: { melee: amount },
          starlight: { morale: amount }
        }.fetch(key.to_sym, {})
      end

      def effect_statuses(key)
        {
          cloak_of_night: %i[ranged_hidden],
          withering: %i[damage_over_time],
          entangled: %i[no_march],
          ember_cage: %i[ember_cage],
          gravity_well: %i[no_march],
          howling_gale: %i[ranged_hindered],
          dusk_hide: %i[magic_ward],
          plague: %i[damage_over_time]
        }.fetch(key.to_sym, [])
      end

      def effect_triggers(key, value)
        amount = value.to_i
        {
          cinder_shield: { after_melee_hit: { damage: 1 } },
          withering: { start_turn: { damage: amount } },
          killing_frenzy: { end_turn: { damage: 1 } },
          ember_cage: { after_move: { damage: amount } },
          plague: { start_turn: { damage: amount, spell_key: :wasting_wind } }
        }.fetch(key.to_sym, {})
      end

      def schedule_comet!(target, value)
        acting_side[:scheduled_spells] ||= []
        event = {
          kind: "comet",
          spell_key: spell.key.to_s,
          caster_id: caster[:actor_id],
          actor_name: caster[:actor_name],
          actor_role: caster[:actor_role],
          target: target,
          power: value.to_i,
          due_round: round_number.to_i + 1
        }
        acting_side[:scheduled_spells] << event
        @effect_log << { kind: "scheduled", spell_key: spell.key.to_s, due_round: event[:due_round] }
        event
      end

      def distance(left, right)
        return 0.0 unless left && right

        Geometry::Battlefield.distance_between(left, right)
      end

      def flank_point(target)
        facing = target[:facing].to_f + 90
        Geometry::Battlefield.move_along_facing(target.merge(facing: facing), 4.0)
      end

      def living(entries)
        Array(entries).select { |entry| entry[:current_health].to_i > 0 }
      end

      def duplicate_effect_penalty(target, spell)
        return 0.0 unless target.is_a?(Hash)

        Array(target[:spell_effects]).any? { |effect| effect[:key].to_s == spell.key.to_s } ? -40.0 : 0.0
      end

      def affect!(target)
        @affected_ids << target[:entity_id]
      end

      def record_summon!(summon, remaining_turns: nil)
        State.sync_combatant_footprint!(summon)
        @summon_ids << summon[:entity_id]
        @affected_ids << summon[:entity_id]
        @effect_log << {
          kind: "summon",
          summon_id: summon[:entity_id],
          summon_kind: summon[:summon_kind].to_s,
          remaining_turns: remaining_turns
        }.compact
        summon
      end

      def expiry_for(target, duration)
        if duration.is_a?(Numeric)
          return { moment: :turns, side_key: target[:side_key], remaining_turns: duration.to_i }
        end

        case duration.to_sym
        when :next_target_turn
          { moment: :end_turn, side_key: target[:side_key] }
        when :current_turn
          { moment: :end_turn, side_key: acting_side[:side_key] }
        when :battle
          { moment: :battle, side_key: acting_side[:side_key] }
        else
          { moment: :start_turn, side_key: acting_side[:side_key] }
        end
      end

      def apply_enemy_facing!(unit)
        enemy = nearest(unit, enemies)
        return unit unless enemy

        desired = Geometry::Battlefield.heading_to(unit, enemy)
        obstacles = Pathing::Obstacles.around(unit, units: all_combatants, terrain: terrain)
        facing = nearest_clear_facing(unit, desired, obstacles, unit[:entity_id])
        unit[:facing] = facing if facing
        unit
      end

      def nearest_clear_facing(unit, desired, obstacles, contact_id)
        return desired if facing_clear?(unit, desired, obstacles, contact_id)

        best = nil
        best_gap = Float::INFINITY
        (1..18).each do |step|
          offset = step * 10.0
          [ offset, -offset ].each do |delta|
            gap = delta.abs
            next if gap >= best_gap

            facing = Geometry::Battlefield.normalize_facing(desired + delta)
            next unless facing_clear?(unit, facing, obstacles, contact_id)

            best = facing
            best_gap = gap
          end
        end
        best
      end

      def facing_clear?(unit, facing, obstacles, contact_id)
        obstacles.clear?(unit.merge(facing: facing), contact_id: contact_id)
      end

      def spell_pose_viable?(unit, pose, obstacles)
        return false unless SpellWorld.inside_battlefield?(pose)

        nearest_clear_facing(
          unit.merge(x: pose[:x], y: pose[:y]),
          pose[:facing] || unit[:facing],
          obstacles,
          unit[:entity_id]
        )
      end

      def summon_prototype(kind)
        profile = SpellWorld::SUMMONS.fetch(kind.to_s)
        files = [ profile.fetch(:models), 3 ].min
        ranks = (profile.fetch(:models).to_f / files).ceil
        {
          entity_id: "summon-preview",
          x: caster[:x],
          y: caster[:y],
          facing: caster[:facing],
          base_width: files.to_f,
          base_depth: ranks.to_f,
          current_health: profile[:health]
        }
      end
    end
  end
end
