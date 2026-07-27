module Sim
  module Battle
    module Phases
      module Melee
        module_function

        def play(acting_side:, target_side:, round_number:, rng:, **)
          phase = AttackResolution.create_phase("melee", "Фаза боя")
          Rules.for(:melee).before_play!(
            phase: phase,
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number
          )
          phase[:allow_routing_melee] = false
          AttackResolution.resolve!(
            phase: phase,
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            attack_type: "melee",
            rng: rng
          )
          phase[:allow_routing_melee] = true
          AttackResolution.resolve!(
            phase: phase,
            acting_side: target_side,
            target_side: acting_side,
            round_number: round_number,
            attack_type: "melee",
            rng: rng
          )
          Morale.resolve_post_melee!(phase: phase, acting_side: acting_side, target_side: target_side, round_number: round_number)
        end
      end
    end
  end
end
