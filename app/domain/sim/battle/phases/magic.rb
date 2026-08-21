module Sim
  module Battle
    module Phases
      module Magic
        module_function

        def play(acting_side:, target_side:, round_number:, rng:, missile_plan: nil, terrain: [], **)
          phase = AttackResolution.create_phase("magic", "Фаза магии")
          known_actor_ids = SpellCasting.casters(acting_side).map { |entry| entry[:caster][:actor_id] }
          SpellCasting.play!(
            phase: phase,
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            rng: rng,
            terrain: terrain
          )
          plan = missile_plan || Missile.plan(
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            terrain: terrain
          )
          legacy_plan = Array(plan).reject { |entry| known_actor_ids.include?(entry[:actor_id]) }
          if legacy_plan.any?
            Missile.play_planned!(
              phase: phase,
              plan: legacy_plan,
              attack_type: "magic",
              acting_side: acting_side,
              target_side: target_side,
              round_number: round_number,
              rng: rng,
              terrain: terrain
            )
          elsif phase[:events].empty?
            AttackResolution.add_event(phase, "Подходящих заклинателей нет.")
            phase[:snapshot] = State.snapshot_battlefield([ acting_side, target_side ])
          end
          Morale.resolve_post_missile!(
            phase: phase,
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            attack_type: "magic",
            terrain: terrain
          )
        end
      end
    end
  end
end
