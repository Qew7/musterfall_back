module Sim
  module Battle
    module Turn
      module_function

      def play(round_number:, acting_side:, target_side:, rng:)
        context = { round_number: round_number, acting_side: acting_side, target_side: target_side, rng: rng }
        {
          player_id: acting_side[:player_id],
          player_name: acting_side[:player_name],
          phases: [
            Phases::Morale.play_start(**context),
            Phases::Movement.play(**context),
            Phases::Magic.play(**context),
            Phases::Shooting.play(**context),
            Phases::Melee.play(**context)
          ]
        }
      end
    end
  end
end
