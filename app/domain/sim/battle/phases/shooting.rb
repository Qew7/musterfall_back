module Sim
  module Battle
    module Phases
      module Shooting
        module_function

        def play(acting_side:, target_side:, round_number:, rng:, missile_plan: nil, terrain: [], **)
          phase = AttackResolution.create_phase("shooting", "Фаза стрельбы")
          plan = missile_plan || Missile.plan(
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            terrain: terrain
          )
          Missile.play_planned!(
            phase: phase,
            plan: plan,
            attack_type: "shooting",
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            rng: rng,
            terrain: terrain
          )
          Morale.resolve_post_missile!(
            phase: phase,
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            attack_type: "shooting",
            terrain: terrain
          )
        end
      end
    end
  end
end
