module Sim
  module Battle
    module Decisions
      # Choose cast vs shoot and build the shared missile plan.
      module MissileChoice
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

        def choose_action(actor, enemies, all_combatants, round_number)
          magic = best_option(actor, enemies, all_combatants, round_number, "magic")
          shooting = best_option(actor, enemies, all_combatants, round_number, "shooting")
          return magic unless shooting
          return shooting unless magic

          magic[:expected] >= shooting[:expected] ? magic : shooting
        end

        def has_missile_option?(actor, enemies, all_combatants, round_number)
          !choose_action(actor, enemies, all_combatants, round_number).nil?
        end

        def best_option(actor, enemies, all_combatants, round_number, attack_type)
          return nil unless Phases::AttackResolution.can_attack?(actor, attack_type)

          selection = Targeting.choose_target(actor, enemies, attack_type, all_combatants)
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
                  damage_fn: Phases::AttackResolution.method(:damage)
                )
              else
                chance = Phases::AttackResolution.hit_chance(actor, entry, "shooting")
                chance * Phases::AttackResolution.damage(actor, entry, "shooting", vector, round_number) * strikes
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
              ranged = host.dig(:contributors, :ranged) || []
              ranged.filter_map do |contributor|
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

          Targeting.can_target_missile?(actor, target, attack_type, all_combatants)
        end

        # Host has no legal cast/shot from current pose (any ranged contributor).
        def host_needs_reposition?(host, enemies, all_combatants, round_number)
          return false unless Roles.missile_seeker?(host)
          return false if host[:current_health].to_i <= 0 || host[:is_routing]

          ranged = host.dig(:contributors, :ranged) || []
          actors = ranged.filter_map do |contributor|
            next unless contributor[:ranged].to_i > 0 || contributor[:spell].to_i > 0

            build_actor(host, contributor)
          end
          return false if actors.empty?

          actors.none? { |actor| has_missile_option?(actor, enemies, all_combatants, round_number) }
        end
      end
    end
  end
end
