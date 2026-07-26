module Sim
  module Battle
    module Phases
      module Magic
        module_function

        def play(acting_side:, target_side:, round_number:, rng:, **)
          phase = AttackResolution.resolve!(
            phase: AttackResolution.create_phase("magic", "Фаза магии"),
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            attack_type: "magic",
            rng: rng
          )
          Morale.resolve_post_missile!(phase: phase, acting_side: acting_side, target_side: target_side, round_number: round_number, attack_type: "magic")
        end
      end
    end
  end
end
