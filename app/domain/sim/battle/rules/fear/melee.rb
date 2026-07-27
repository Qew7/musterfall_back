module Sim
  module Battle
    module Rules
      module Fear
        # Fear assault gate for the melee phase.
        # Attacker fear → defender fails ⇒ cannot attack this round.
        # Defender fear → attacker fails ⇒ assault cancelled (cannot attack this round).
        # Both have fear → normal (no special check).
        module Melee
          module_function

          def has_fear?(combatant)
            Array(combatant[:abilities]).include?("fear")
          end

          def clear!(combatants)
            Array(combatants).each do |combatant|
              combatant.delete(:fear_cannot_attack)
              combatant.delete(:fear_check_note)
            end
          end

          def before_play!(ctx)
            phase = ctx.fetch(:phase)
            left_side = ctx.fetch(:acting_side)
            right_side = ctx.fetch(:target_side)
            round_number = ctx.fetch(:round_number)
            clear!(left_side[:combatants])
            clear!(right_side[:combatants])

            pairs = engaged_pairs(left_side, right_side)
            pairs.each_with_index do |(left, right), index|
              resolve_pair!(
                phase: phase,
                attacker: left,
                defender: right,
                allies: left_side[:combatants],
                enemies: right_side[:combatants],
                battle_sides: [ left_side, right_side ],
                round_number: round_number,
                sequence: index * 2
              )
              resolve_pair!(
                phase: phase,
                attacker: right,
                defender: left,
                allies: right_side[:combatants],
                enemies: left_side[:combatants],
                battle_sides: [ left_side, right_side ],
                round_number: round_number,
                sequence: (index * 2) + 1
              )
            end
          end

          def resolve_pair!(phase:, attacker:, defender:, allies:, enemies:, battle_sides:, round_number:, sequence:)
            return if attacker[:current_health].to_i <= 0 || defender[:current_health].to_i <= 0
            return if attacker[:is_routing] || defender[:is_routing]

            attacker_fear = has_fear?(attacker)
            defender_fear = has_fear?(defender)
            return if attacker_fear == defender_fear

            if attacker_fear && !defender_fear
              apply_check!(
                phase: phase,
                subject: defender,
                allies: enemies,
                foes: allies,
                battle_sides: battle_sides,
                round_number: round_number,
                sequence: sequence,
                reason: "fear_from_attacker",
                source: attacker,
                fail_summary: "#{defender[:name]} не выдерживает страх #{attacker[:name]} и не атакует в этом раунде.",
                pass_summary: "#{defender[:name]} держит строй против страха #{attacker[:name]}."
              )
            elsif defender_fear && !attacker_fear
              apply_check!(
                phase: phase,
                subject: attacker,
                allies: allies,
                foes: enemies,
                battle_sides: battle_sides,
                round_number: round_number,
                sequence: sequence,
                reason: "fear_from_defender",
                source: defender,
                fail_summary: "#{attacker[:name]} не решается напасть на #{defender[:name]} (страх) — нападение не состоится.",
                pass_summary: "#{attacker[:name]} преодолевает страх перед #{defender[:name]} и идёт в атаку."
              )
            end
          end

          def apply_check!(phase:, subject:, allies:, foes:, battle_sides:, round_number:, sequence:, reason:, source:, fail_summary:, pass_summary:)
            return if subject[:fear_cannot_attack]

            before = State.snapshot_combatant(subject)
            check = Phases::Morale.resolve_check(
              combatant: subject,
              allies: allies,
              enemies: foes,
              round_number: round_number,
              phase_type: "fear",
              combat_score_delta: 0,
              sequence: sequence
            )
            subject[:fear_cannot_attack] = !check[:passed]
            subject[:fear_check_note] = reason
            summary = check[:passed] ? pass_summary : fail_summary
            action = {
              type: "fear_check",
              actor_id: subject[:entity_id],
              actor_unit_id: subject[:entity_id],
              actor_name: subject[:name],
              actor_role: subject[:kind] == "hero" ? "hero" : "unit",
              target_id: source[:entity_id],
              target_name: source[:name],
              vector: nil,
              damage: 0,
              summary: summary,
              morale_check: check.merge(trigger: { reason: reason, source_id: source[:entity_id], source_name: source[:name] }),
              actor_state: before,
              target_state_before: before,
              target_state_after: State.snapshot_combatant(subject),
              snapshot: State.snapshot_battlefield(battle_sides),
              details: fear_details(subject, source, check, reason, summary)
            }
            phase[:actions] << action
            Phases::AttackResolution.add_event(phase, summary)
          end

          def engaged_pairs(left_side, right_side)
            engage = Phases::AttackResolution::CONTACT + Geometry::Battlefield::CONFIG[:contact_snap]
            pairs = []
            left_side[:combatants].each do |left|
              next if left[:current_health].to_i <= 0

              right_side[:combatants].each do |right|
                next if right[:current_health].to_i <= 0
                next unless Geometry::Battlefield.distance_between_units(left, right) <= engage

                pairs << [ left, right ]
              end
            end
            pairs
          end

          def fear_details(subject, source, check, reason, summary)
            [
              "fear_check reason=#{reason} subject=#{subject[:entity_id]} vs=#{source[:entity_id]}",
              "roll=#{check[:roll]} threshold=#{check[:threshold]} passed=#{check[:passed]} morale=#{check[:effective_morale]} source=#{check[:source]}",
              "result=#{subject[:fear_cannot_attack] ? "cannot_attack" : "ok"}",
              "summary=#{summary}"
            ]
          end

          def allow_attack?(attacker, _ctx = nil)
            !attacker[:fear_cannot_attack]
          end

          def blocked?(combatant)
            !!combatant[:fear_cannot_attack]
          end
        end
      end
    end
  end
end
