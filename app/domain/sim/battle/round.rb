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

        round[:events].concat(State.apply_faction_passives!(battle[:sides][:left], enemy_side: battle[:sides][:right], terrain: terrain, rng: rng))
        round[:events].concat(State.apply_faction_passives!(battle[:sides][:right], enemy_side: battle[:sides][:left], terrain: terrain, rng: rng))
        end_phase = Phases::AttackResolution.create_phase("start", "Конец раунда")
        Rules.for(:round).after_play!(
          phase: end_phase, sides: battle[:sides].values, round_number: round_number,
          terrain: terrain, rng: rng
        )
        if end_phase[:actions].any?
          end_phase[:snapshot] = State.snapshot_battlefield(battle[:sides].values)
          if round[:turns].last
            round[:turns].last[:phases] << end_phase
          else
            side = battle[:sides][:left]
            round[:turns] << { player_id: side[:player_id], player_name: side[:player_name], phases: [ end_phase ] }
          end
        end
        round[:events].concat(State.resolve_summons_end_round!(battle[:sides][:left]))
        round[:events].concat(State.resolve_summons_end_round!(battle[:sides][:right]))
        round
      end
    end
  end
end
