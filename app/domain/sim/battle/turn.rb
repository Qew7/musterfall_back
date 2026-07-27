module Sim
  module Battle
    module Turn
      module_function

      # Phase order: start morale → movement → magic/shooting (planned after move) → melee.
      def play(round_number:, acting_side:, target_side:, rng:)
        context = { round_number: round_number, acting_side: acting_side, target_side: target_side, rng: rng }
        start_phase = Phases::Morale.play_start(**context)
        movement_phase = Phases::Movement.play(**context)
        missile_plan = Phases::Missile.plan(**context)
        context = context.merge(missile_plan: missile_plan)
        {
          player_id: acting_side[:player_id],
          player_name: acting_side[:player_name],
          phases: [
            start_phase,
            movement_phase,
            Phases::Magic.play(**context),
            Phases::Shooting.play(**context),
            Phases::Melee.play(**context)
          ]
        }
      end
    end
  end
end
