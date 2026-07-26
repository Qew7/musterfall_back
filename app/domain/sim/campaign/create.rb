module Sim
  module Campaign
    class Create
      def self.call(player_count:)
        new(player_count).call
      end

      def initialize(player_count)
        @player_count = player_count.to_i
      end

      def call
        return Result.failure("player_count must be at least 2") if @player_count < 2

        players = Array.new(@player_count) do |index|
          {
            id: "player-#{index + 1}",
            name: index.zero? ? "Полководец 1" : "Бот #{index}",
            is_bot: index.positive?,
            status: "active",
            faction_id: nil,
            treasury: Constants::STARTING_TREASURY,
            roster: [],
            victories: 0,
            round_notes: []
          }
        end

        Result.ok(State.new(round: 1, winner_id: nil, last_round_report: nil, players: players, id_sequence: 0, version: 0))
      end
    end
  end
end
