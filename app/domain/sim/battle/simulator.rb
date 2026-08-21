module Sim
  module Battle
    class Simulator
      def self.call(player_a, player_b, catalog, rng:, terrain: nil, map_seed: nil)
        new(player_a, player_b, catalog, rng, terrain: terrain, map_seed: map_seed).call
      end

      def initialize(player_a, player_b, catalog, rng, terrain: nil, map_seed: nil)
        @player_a = player_a
        @player_b = player_b
        @catalog = catalog
        @rng = rng
        source = Array(terrain || TerrainMap.generate(seed: map_seed || 0))
        @terrain = source.map(&:dup)
        @map_terrain = @terrain.map(&:dup)
      end

      def call
        battle = State.create(@player_a, @player_b, @catalog, terrain: @terrain)
        initial_snapshot = State.snapshot_battlefield([ battle[:sides][:left], battle[:sides][:right] ])

        (1..Constants::MAX_BATTLE_ROUNDS).each do |round_number|
          break unless State.living?(battle[:sides][:left]) && State.living?(battle[:sides][:right])
          break if State.all_routing?([ battle[:sides][:left], battle[:sides][:right] ])

          battle[:rounds] << Round.play(battle: battle, round_number: round_number, rng: @rng)
        end

        score_a = State.victory_score(battle[:sides][:left], battle[:sides][:right])
        score_b = State.victory_score(battle[:sides][:right], battle[:sides][:left])
        winner_id = (score_a <=> score_b) >= 0 ? @player_a[:id] : @player_b[:id]
        total_a = score_a[0]
        total_b = score_b[0]
        State.sync_battle!(battle)

        {
          battle_id: "#{@player_a[:id]}-#{@player_b[:id]}-r#{@rng.rand(1_000_000_000)}",
          rounds: battle[:rounds],
          initial_snapshot: initial_snapshot,
          terrain: @map_terrain,
          left: State.snapshot_side(@player_a, battle[:sides][:left], @catalog),
          right: State.snapshot_side(@player_b, battle[:sides][:right], @catalog),
          winner_id: winner_id,
          winner_name: winner_id == @player_a[:id] ? @player_a[:name] : @player_b[:name],
          summary: "#{@player_a[:name]} #{total_a} vs #{total_b} #{@player_b[:name]}",
          events: flatten_events(battle[:rounds]).first(24)
        }
      end

      private

      def flatten_events(rounds)
        rounds.flat_map do |round|
          turn_events = round[:turns].flat_map do |turn|
            phase_events = turn[:phases].flat_map do |phase|
              if phase[:actions].any?
                phase[:actions].map { |action| action[:summary] }
              else
                phase[:events].first(1).map { |entry| "#{phase[:label]}: #{entry}" }
              end
            end
            [ "Ход игрока: #{turn[:player_name]}", *phase_events ]
          end
          [ "Раунд #{round[:number]}", *turn_events, *round[:events] ]
        end
      end
    end
  end
end
