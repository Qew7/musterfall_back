module Sim
  module Battle
    module Phases
      module Magic
        module_function

        def play(acting_side:, target_side:, round_number:, rng:, missile_plan: nil, **)
          phase = AttackResolution.create_phase("magic", "Фаза магии")
          plan = missile_plan || Missile.plan(
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number
          )
          Missile.play_planned!(
            phase: phase,
            plan: plan,
            attack_type: "magic",
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            rng: rng
          )
          Morale.resolve_post_missile!(phase: phase, acting_side: acting_side, target_side: target_side, round_number: round_number, attack_type: "magic")
        end
      end
    end
  end
end
