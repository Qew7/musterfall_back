module Sim
  module Battle
    module Phases
      module Shooting
        module_function

        def play(acting_side:, target_side:, round_number:, rng:, missile_plan: nil, terrain: [], **)
          phase = AttackResolution.create_phase("shooting", "Фаза стрельбы")
          context = {
            phase: phase,
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            terrain: terrain
          }
          Rules.for(:shooting).before_play!(context)
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
          result = Morale.resolve_post_missile!(
            phase: phase,
            acting_side: acting_side,
            target_side: target_side,
            round_number: round_number,
            attack_type: "shooting",
            terrain: terrain
          )
          Rules.for(:shooting).after_play!(context.merge(phase: result))
          result
        end
      end
    end
  end
end
