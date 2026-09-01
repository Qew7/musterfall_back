module Sim
  module Battle
    module Rules
      module Fear
        # Fear checks only on charge into contact — not while already engaged.
        # Non-fear charger vs fear target: charger checks, fail ⇒ halt halfway.
        # Fear charger vs non-fear target: target checks, fail ⇒ cannot attack this round.
        module Movement
          # rule: fear | movement | Charge fear checks between charger and defender; may halt charge or forbid defender attacks.
          module_function

          def has_fear?(combatant)
            Array(combatant[:abilities]).include?("fear")
          end

          def fearless?(combatant, terrain: [])
            return true if Array(combatant[:abilities]).include?("fearless")

            Wildborn::Movement.fearless?(combatant, terrain: terrain)
          end

          def prepare_melee_intents!(ctx)
            phase = ctx.fetch(:phase)
            intents = ctx.fetch(:intents)
            acting_side = ctx.fetch(:acting_side)
            target_side = ctx.fetch(:target_side)
            round_number = ctx.fetch(:round_number)
            terrain = Array(ctx[:terrain])
            enemies = target_side[:combatants]
            sync_round!(acting_side[:combatants], round_number)
            sync_round!(target_side[:combatants], round_number)

            intents.each_with_index do |intent, index|
              next unless charge_intent?(intent, enemies)

              combatant = intent[:combatant]
              target = intent[:nearest]

              if charge_into_fear?(combatant, target, terrain: terrain)
                next if combatant[:fear_charge_check_round].to_i == round_number.to_i

                apply_charger_check!(
                  intent: intent,
                  phase: phase,
                  combatant: combatant,
                  target: target,
                  allies: acting_side[:combatants],
                  foes: enemies,
                  battle_sides: [ acting_side, target_side ],
                  round_number: round_number,
                  sequence: index
                )
              elsif fear_charges_defender?(combatant, target, terrain: terrain)
                next if target[:fear_defender_check_round].to_i == round_number.to_i

                apply_defender_check!(
                  phase: phase,
                  subject: target,
                  source: combatant,
                  subject_allies: target_side[:combatants],
                  source_allies: acting_side[:combatants],
                  battle_sides: [ acting_side, target_side ],
                  round_number: round_number,
                  sequence: index,
                  terrain: terrain
                )
              end
            end
          end

          def charge_intent?(intent, enemies)
            target = intent[:nearest]
            return false unless target
            return false if intent[:wait] || intent[:destination].nil?
            return false unless intent[:charge_contact_id]

            from = intent[:from] || intent[:combatant]
            at_start = intent[:combatant].merge(x: from[:x], y: from[:y], facing: from[:facing])
            return false if Decisions::Movement.engaged?(at_start, target)

            Decisions::ChargeRange.within?(at_start, target, enemies: enemies)
          end

          def charge_into_fear?(combatant, target, terrain: [])
            return false if has_fear?(combatant) || fearless?(combatant, terrain: terrain)
            return false unless has_fear?(target)

            true
          end

          def fear_charges_defender?(combatant, target, terrain: [])
            return false unless has_fear?(combatant)
            return false if has_fear?(target) || fearless?(target, terrain: terrain)

            true
          end

          def apply_charger_check!(intent:, phase:, combatant:, target:, allies:, foes:, battle_sides:, round_number:, sequence:)
            before = State.snapshot_combatant(combatant)
            check = Phases::Morale.resolve_check(
              combatant: combatant,
              allies: allies,
              enemies: foes,
              round_number: round_number,
              phase_type: "fear",
              combat_score_delta: 0,
              sequence: sequence
            )
            combatant[:fear_charge_check_round] = round_number.to_i

            if check[:passed]
              summary = "#{combatant[:name]} преодолевает страх перед #{target[:name]} и идёт в атаку."
              push_fear_action!(
                phase: phase, combatant: combatant, target: target, check: check, summary: summary,
                before: before, battle_sides: battle_sides, trigger: "charge", result: "passed"
              )
            else
              halt_charge!(intent)
              summary = "#{combatant[:name]} не выдерживает страх #{target[:name]} — заряд останавливается на полпути."
              push_fear_action!(
                phase: phase, combatant: combatant, target: target, check: check, summary: summary,
                before: before, battle_sides: battle_sides, trigger: "charge", result: "charge_halted"
              )
            end
          end

          def apply_defender_check!(phase:, subject:, source:, subject_allies:, source_allies:, battle_sides:, round_number:, sequence:, terrain: [])
            return if has_fear?(subject) || fearless?(subject, terrain: terrain)

            before = State.snapshot_combatant(subject)
            check = Phases::Morale.resolve_check(
              combatant: subject,
              allies: subject_allies,
              enemies: source_allies,
              round_number: round_number,
              phase_type: "fear",
              combat_score_delta: 0,
              sequence: sequence + 1000
            )
            subject[:fear_defender_check_round] = round_number.to_i
            subject[:fear_cannot_attack] = !check[:passed]
            summary =
              if check[:passed]
                "#{subject[:name]} держит строй против страха #{source[:name]}."
              else
                "#{subject[:name]} не выдерживает страх #{source[:name]} и не атакует в этом раунде."
              end
            push_fear_action!(
              phase: phase, combatant: subject, target: source, check: check, summary: summary,
              before: before, battle_sides: battle_sides, trigger: "fear_from_attacker",
              result: check[:passed] ? "passed" : "attack_blocked"
            )
          end

          def sync_round!(combatants, round_number)
            Array(combatants).each do |combatant|
              next if combatant[:fear_sync_round].to_i == round_number.to_i

              combatant.delete(:fear_cannot_attack)
              combatant.delete(:fear_charge_check_round)
              combatant.delete(:fear_defender_check_round)
              combatant[:fear_sync_round] = round_number.to_i
            end
          end

          def halt_charge!(intent)
            from = intent[:from]
            desired = intent[:destination]
            combatant = intent[:combatant]
            target = intent[:nearest]
            halted = fear_halt_pose(from, desired, combatant, target)

            intent[:destination] = Geometry::Battlefield.footprint_destination(halted)
            intent.delete(:paid_destination)
            intent[:free_align] = false
            intent[:charge_contact_id] = nil
            intent[:plan] = (intent[:plan] || {}).merge(truncated: true, fear_halted: true, charge: false)
          end

          def fear_halt_pose(from, desired, combatant, target)
            pose = lerp_pose(from, desired, combatant, 0.5)
            return pose unless Decisions::Movement.engaged?(pose, target)

            (1..10).each do |step|
              t = 0.5 - (step * 0.05)
              break if t <= 0

              pose = lerp_pose(from, desired, combatant, t)
              return pose unless Decisions::Movement.engaged?(pose, target)
            end

            combatant.merge(x: from[:x], y: from[:y], facing: from[:facing])
          end

          def lerp_pose(from, desired, combatant, ratio)
            from_facing = from[:facing].to_f
            facing_delta = Geometry::Battlefield.shortest_facing_delta(from_facing, desired[:facing])
            pose = combatant.merge(
              x: from[:x].to_f + ((desired[:x].to_f - from[:x].to_f) * ratio),
              y: from[:y].to_f + ((desired[:y].to_f - from[:y].to_f) * ratio),
              facing: Geometry::Battlefield.normalize_facing(from_facing + (facing_delta * ratio))
            )
            Geometry::Battlefield.apply_footprint!(pose, desired)
            pose
          end

          def push_fear_action!(phase:, combatant:, target:, check:, summary:, before:, battle_sides:, trigger:, result:)
            action = {
              type: "fear_check",
              actor_id: combatant[:entity_id],
              actor_unit_id: combatant[:entity_id],
              actor_name: combatant[:name],
              actor_role: combatant[:kind] == "hero" ? "hero" : "unit",
              target_id: target[:entity_id],
              target_name: target[:name],
              vector: nil,
              damage: 0,
              summary: summary,
              morale_check: check.merge(trigger: { reason: trigger, source_id: target[:entity_id], source_name: target[:name] }),
              trace: Trace.build(
                rule_keys: [ "fear" ],
                trigger: trigger,
                result: result,
                target_ids: [ target[:entity_id] ]
              ),
              actor_state: before,
              target_state_before: before,
              target_state_after: State.snapshot_combatant(combatant),
              snapshot: State.snapshot_battlefield(battle_sides),
              details: fear_details(combatant, target, check, summary, result)
            }
            phase[:actions] << action
            Phases::AttackResolution.add_event(phase, summary)
          end

          def fear_details(subject, source, check, summary, result)
            [
              "fear_check reason=#{result} subject=#{subject[:entity_id]} vs=#{source[:entity_id]}",
              "roll=#{check[:roll]} threshold=#{check[:threshold]} passed=#{check[:passed]} morale=#{check[:effective_morale]} source=#{check[:source]}",
              "result=#{result}",
              "summary=#{summary}"
            ]
          end
        end
      end
    end
  end
end
