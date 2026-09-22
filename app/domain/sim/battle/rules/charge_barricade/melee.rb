module Sim
  module Battle
    module Rules
      module ChargeBarricade
        module Melee
          MINIMUM_CHARGE = 4.0
          MAXIMUM_DAMAGE = 6

          # rule: charge_barricade | melee | A braced frontal defender cancels a charge of at least four inches and deals one reactive damage per two inches, capped at six.
          module_function

          def army_role(profile)
            :frontline if Array(profile[:abilities]).include?("chargeBarricade")
          end

          def protected?(attacker, defender)
            Array(defender[:abilities]).include?("chargeBarricade") && defender.fetch(:barricade_braced, true) &&
              !defender[:is_routing] && defender[:current_health].to_f.positive? &&
              attacker[:charged_distance].to_f >= MINIMUM_CHARGE &&
              attacker[:charged_target_id] == defender[:entity_id] &&
              Geometry::Battlefield.classify_attack_vector(attacker, defender) == "front"
          end

          def prepare_profile(profile, host, defender, attack_type)
            return profile unless attack_type.to_s == "melee" && protected?(host, defender)

            profile.merge(charged_distance: 0)
          end

          def before_play!(ctx)
            sides = [ ctx[:acting_side], ctx[:target_side] ]
            sides.each do |side|
              foes = sides.reject { |other| other.equal?(side) }.flat_map { |other| other[:combatants] }
              side[:combatants].each do |charger|
                next unless charger[:current_health].to_f.positive?

                defender = foes.find { |foe| foe[:entity_id] == charger[:charged_target_id] }
                next unless defender && protected?(charger, defender)
                next unless Geometry::Battlefield.melee_contact?(charger, defender)

                distance = charger[:charged_distance].to_f
                before = State.snapshot_combatant(charger)
                damage = [ (distance / 2).floor, MAXIMUM_DAMAGE, charger[:current_health].to_i ].min
                charger[:current_health] -= damage
                charger[:charged_distance] = 0
                State.sync_combatant_footprint!(charger)
                summary = "#{defender[:name]} останавливает натиск #{charger[:name]}: #{damage} ответного урона, бонус заряда отменён."
                Phases::AttackResolution.add_event(ctx[:phase], summary)
                ctx[:phase][:actions] << {
                  type: "charge_barricade", actor_id: defender[:entity_id], actor_name: defender[:name],
                  target_id: charger[:entity_id], target_name: charger[:name], damage: damage,
                  summary: summary, details: [ "charge_barricade charged_distance=#{distance} reactive_damage=#{damage} vector=front" ],
                  target_state_before: before, target_state_after: State.snapshot_combatant(charger),
                  snapshot: State.snapshot_battlefield(sides),
                  trace: Trace.build(rule_keys: [ "chargeBarricade" ], trigger: "frontal_charge", result: "countered", target_ids: [ charger[:entity_id] ])
                }
              end
            end
          end
        end
      end
    end
  end
end
