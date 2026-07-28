module Sim
  module Battle
    module Phases
      # Plans and resolves magic/shooting so each missile actor casts OR shoots once.
      module Missile
        module_function

        def plan(**kwargs)
          Decisions::MissileChoice.plan(**kwargs)
        end

        def play_planned!(phase:, plan:, attack_type:, acting_side:, target_side:, round_number:, rng:, terrain: [])
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

            contributor = (host.dig(:contributors, :ranged) || []).find { |item| item[:entity_id] == entry[:actor_id] }
            next unless contributor

            actor = Decisions::MissileChoice.build_actor(host, contributor)
            target = target_side[:combatants].find { |enemy| enemy[:entity_id] == entry[:target_id] }
            next unless target && target[:current_health].to_i > 0

            unless Decisions::MissileChoice.valid_target?(actor, target, attack_type, all_combatants, terrain: terrain)
              selection = Decisions::Targeting.choose_target(
                actor, target_side[:combatants], attack_type, all_combatants, terrain: terrain
              )
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
              rng: rng,
              terrain: terrain
            )
          end

          AttackResolution.add_event(phase, "Эта фаза прошла без результата.") if phase[:events].empty?
          phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          phase
        end

        def choose_action(...)
          Decisions::MissileChoice.choose_action(...)
        end

        def best_option(...)
          Decisions::MissileChoice.best_option(...)
        end

        def expected_damage(...)
          Decisions::MissileChoice.expected_damage(...)
        end

        def missile_actors(...)
          Decisions::MissileChoice.missile_actors(...)
        end

        def build_actor(...)
          Decisions::MissileChoice.build_actor(...)
        end

        def valid_target?(...)
          Decisions::MissileChoice.valid_target?(...)
        end
      end
    end
  end
end
