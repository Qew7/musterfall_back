module Sim
  module Battle
    module Phases
      # Plans and resolves magic/shooting so each missile actor casts OR shoots once.
      module Missile
        module_function

        def plan(acting_side:, target_side:, round_number:, **)
          all_combatants = acting_side[:combatants] + target_side[:combatants]
          actors = missile_actors(acting_side).sort_by { |actor| -actor[:initiative].to_i }

          actors.filter_map do |actor|
            choice = choose_action(actor, target_side[:combatants], all_combatants, round_number)
            next unless choice

            choice.merge(
              key: actor[:key],
              host_id: actor[:host_id],
              actor_id: actor[:actor_id],
              actor_name: actor[:actor_name],
              actor_role: actor[:actor_role],
              initiative: actor[:initiative]
            )
          end
        end

        def play_planned!(phase:, plan:, attack_type:, acting_side:, target_side:, round_number:, rng:)
          planned = Array(plan).select { |entry| entry[:attack_type] == attack_type }
          if planned.empty?
            AttackResolution.add_event(phase, "Подходящих атакующих нет.")
            phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
            return phase
          end

          hosts = acting_side[:combatants].index_by { |entry| entry[:entity_id] }
          all_combatants = acting_side[:combatants] + target_side[:combatants]

          planned.each do |entry|
            host = hosts[entry[:host_id]]
            next unless host && host[:current_health].to_i > 0 && !host[:is_routing]

            contributor = (host[:contributors][:ranged] || []).find { |item| item[:entity_id] == entry[:actor_id] }
            next unless contributor

            actor = build_actor(host, contributor)
            target = target_side[:combatants].find { |enemy| enemy[:entity_id] == entry[:target_id] }
            next unless target && target[:current_health].to_i > 0

            unless valid_target?(actor, target, attack_type, all_combatants)
              selection = AttackResolution.choose_target(actor, target_side[:combatants], attack_type, all_combatants)
              next unless selection

              target = selection[:target]
              entry = entry.merge(vector: selection[:vector], target_id: target[:entity_id])
            end

            AttackResolution.resolve_missile_strike!(
              phase: phase,
              actor: actor,
              target: target,
              vector: entry[:vector],
              attack_type: attack_type,
              acting_side: acting_side,
              target_side: target_side,
              round_number: round_number,
              rng: rng
            )
          end

          AttackResolution.add_event(phase, "Эта фаза прошла без результата.") if phase[:events].empty?
          phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          phase
        end

        def choose_action(actor, enemies, all_combatants, round_number)
          magic = best_option(actor, enemies, all_combatants, round_number, "magic")
          shooting = best_option(actor, enemies, all_combatants, round_number, "shooting")
          return magic unless shooting
          return shooting unless magic

          magic[:expected] >= shooting[:expected] ? magic : shooting
        end

        def best_option(actor, enemies, all_combatants, round_number, attack_type)
          return nil unless AttackResolution.can_attack?(actor, attack_type)

          selection = AttackResolution.choose_target(actor, enemies, attack_type, all_combatants)
          return nil unless selection

          target = selection[:target]
          vector = selection[:vector]
          expected = expected_damage(actor, target, vector, round_number, attack_type, enemies)
          return nil if expected <= 0

          {
            attack_type: attack_type,
            target_id: target[:entity_id],
            vector: vector,
            expected: expected
          }
        end

        def expected_damage(actor, target, vector, round_number, attack_type, enemies)
          victims = Geometry::Battlefield.attack_victims(actor, target, enemies, attack_type)
          victims.sum do |victim|
            entry = victim[:target]
            strikes = [ actor[:missile_attacks].to_i, 1 ].max
            strike =
              if attack_type == "magic"
                SpellCasting.expected_damage(
                  actor,
                  entry,
                  vector: vector,
                  round_number: round_number,
                  attacks: strikes,
                  damage_fn: AttackResolution.method(:damage)
                )
              else
                chance = AttackResolution.hit_chance(actor, entry, "shooting")
                chance * AttackResolution.damage(actor, entry, "shooting", vector, round_number) * strikes
              end

            # Armor is inside damage(); living models bias toward larger formations / denser targets.
            models = [ entry[:models_remaining].to_i, 1 ].max
            capped = [ strike * victim[:multiplier].to_f, entry[:current_health].to_f ].min
            capped * (1.0 + Math.log(models + 1, 10) * 0.15)
          end
        end

        def missile_actors(acting_side)
          acting_side[:combatants]
            .select { |host| host[:current_health].to_i > 0 && !host[:is_routing] }
            .flat_map do |host|
              (host[:contributors][:ranged] || []).filter_map do |contributor|
                next unless contributor[:ranged].to_i > 0 || contributor[:spell].to_i > 0

                build_actor(host, contributor)
              end
            end
        end

        def build_actor(host, contributor)
          host.merge(
            key: "#{host[:entity_id]}:#{contributor[:entity_id]}",
            host_id: host[:entity_id],
            actor_id: contributor[:entity_id],
            actor_name: contributor[:name],
            actor_role: contributor[:kind] == "hero" ? "hero" : "unit",
            ranged: contributor[:ranged].to_i,
            spell: contributor[:spell].to_i,
            skill: contributor[:skill] || host[:skill],
            weapon_type: contributor[:weapon_type] || host[:weapon_type],
            abilities: Array(contributor[:abilities]).dup,
            shooting_range: contributor[:shooting_range] || host[:shooting_range],
            spell_range: contributor[:spell_range] || host[:spell_range],
            shooting_template: contributor[:shooting_template] || host[:shooting_template],
            spell_template: contributor[:spell_template] || host[:spell_template],
            requires_line_of_sight: contributor.key?(:requires_line_of_sight) ? contributor[:requires_line_of_sight] : host[:requires_line_of_sight],
            missile_attacks: contributor[:missile_attacks] || host[:missile_attacks] || 1,
            initiative: contributor[:initiative] || host[:initiative],
            contributor: contributor,
            # Targeting uses host footprint/facing; skirmisher on host opens the arc for attached shooters.
            targeting_abilities: (Array(host[:abilities]) + Array(contributor[:abilities])).uniq
          )
        end

        def valid_target?(actor, target, attack_type, all_combatants)
          return false if target[:current_health].to_i <= 0
          return true if attack_type == "magic"

          AttackResolution.can_target_ranged?(actor, target, all_combatants)
        end
      end
    end
  end
end
