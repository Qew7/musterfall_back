module Sim
  module Battle
    module Rules
      module LavaSpit
        module Round
          # rule: lava_spit | round | End of round: each model spits once at engaged foe; flat base damage, no facing/armor/shield rules.
          module_function

          def apply_passives!(side)
            enemies = Array(side.dig(:enemy_side, :combatants))
            return [] if enemies.empty?

            rng = side[:rng]
            all_combatants = side[:combatants] + enemies
            side[:combatants].flat_map do |combatant|
              next [] unless Array(combatant[:abilities]).include?("lavaSpit")
              next [] unless combatant[:current_health].to_i.positive?

              models = combatant[:models_remaining].to_i
              next [] unless models.positive?

              models.times.filter_map do
                spit_once!(combatant, enemies, all_combatants, rng: rng)
              end
            end
          end

          def spit_once!(attacker, enemies, all_combatants, rng:)
            selection = Decisions::Targeting.choose_target(attacker, enemies, "melee", all_combatants)
            return nil unless selection

            target = selection[:target]
            vector = selection[:vector]
            return nil if target[:current_health].to_i <= 0

            attack = Phases::AttackResolution
            return nil unless attack.hit?(attacker, target, "melee", rng)

            before = State.snapshot_combatant(target)
            damage = defenseless_damage(attacker)
            return nil if damage <= 0

            target[:current_health] = [ 0, target[:current_health].to_i - damage ].max
            State.sync_combatant_footprint!(target)
            ActionResult.text_for(
              actor: { actor_name: attacker[:name], actor_role: "unit" },
              action: { type: "melee", vector: vector },
              before: [ before ],
              after: [ State.snapshot_combatant(target) ],
              damage: damage,
              clauses: [ "лавовый харчок: плоский урон, без брони и геометрии удара" ]
            )
          end
          private_class_method :spit_once!

          def defenseless_damage(attacker)
            base = Phases::AttackResolution.base_power(attacker, "melee")
            return 0 if base <= 0

            [ 1, (base / 2.2).round ].max
          end
          private_class_method :defenseless_damage
        end
      end
    end
  end
end
