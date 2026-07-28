module Sim
  module Battle
    module Round
      module_function

      def play(battle:, round_number:, rng:)
        round = { number: round_number, turns: [], events: [] }
        pairs = [
          { acting_side: battle[:sides][:left], target_side: battle[:sides][:right] },
          { acting_side: battle[:sides][:right], target_side: battle[:sides][:left] }
        ]
        terrain = Array(battle[:terrain])

        pairs.each do |pair|
          next unless State.living?(pair[:acting_side]) && State.living?(pair[:target_side])
          next if State.all_routing?([ pair[:acting_side], pair[:target_side] ])

          round[:turns] << Turn.play(
            round_number: round_number,
            acting_side: pair[:acting_side],
            target_side: pair[:target_side],
            rng: rng,
            terrain: terrain
          )
        end

        round[:events].concat(State.apply_faction_passives!(battle[:sides][:left]))
        round[:events].concat(State.apply_faction_passives!(battle[:sides][:right]))
        round
      end
    end
  end
end
