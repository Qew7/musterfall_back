module Sim
  module Persistence
    class BattleWriter
      def self.persist!(game, battle_report, round_number:, as_new: false)
        new(game).persist!(battle_report, round_number: round_number, as_new: as_new)
      end

      def initialize(game)
        @game = game
      end

      def persist!(battle_report, round_number:, as_new: false)
        payload = normalize_report(battle_report, round_number)
        identity = {
          round_number: payload[:round_number],
          left_player_id: payload[:left_player_id],
          right_player_id: payload[:right_player_id]
        }
        battle = if as_new
          @game.battles.new
        else
          @game.battles.where(identity).order(:id).first || @game.battles.new(identity)
        end
        battle.assign_attributes(
          round_number: payload[:round_number],
          left_player_id: payload[:left_player_id],
          right_player_id: payload[:right_player_id],
          left_player_name: payload[:left_player_name],
          right_player_name: payload[:right_player_name],
          winner_id: payload[:winner_id],
          winner_name: payload[:winner_name],
          summary: payload[:summary],
          left_payload: payload[:left_payload],
          right_payload: payload[:right_payload],
          events: payload[:events]
        )
        battle.save!
        replace_rounds!(battle, payload[:rounds])
        battle
      end

      private

      def normalize_report(report, round_number)
        left = deep_stringify(report[:left] || report["left"] || {})
        right = deep_stringify(report[:right] || report["right"] || {})
        {
          round_number: round_number,
          left_player_id: report[:winner_id] && (report.dig(:left, :player_id) || left["player_id"] || left["playerId"]),
          left_player_name: left["player_name"] || left["playerName"],
          right_player_id: right["player_id"] || right["playerId"],
          right_player_name: right["player_name"] || right["playerName"],
          winner_id: report[:winner_id] || report["winnerId"],
          winner_name: report[:winner_name] || report["winnerName"],
          summary: report[:summary] || report["summary"],
          left_payload: left,
          right_payload: right,
          events: Array(report[:events] || report["events"]),
          rounds: normalize_rounds(report[:rounds] || report["rounds"] || [])
        }.tap do |payload|
          payload[:left_player_id] = report.dig(:left, :player_id) || left["player_id"] || left["playerId"]
          payload[:left_player_name] = report.dig(:left, :player_name) || left["player_name"] || left["playerName"]
        end
      end

      def normalize_rounds(rounds)
        Array(rounds).each_with_index.map do |round, _index|
          {
            number: round[:number] || round["number"],
            events: Array(round[:events] || round["events"]),
            turns: Array(round[:turns] || round["turns"]).each_with_index.map do |turn, turn_index|
              {
                position: turn[:position] || turn["position"] || turn_index + 1,
                player_id: turn[:player_id] || turn["playerId"] || turn["player_id"],
                player_name: turn[:player_name] || turn["playerName"] || turn["player_name"],
                phases: Array(turn[:phases] || turn["phases"]).each_with_index.map do |phase, phase_index|
                  {
                    position: phase[:position] || phase["position"] || phase_index + 1,
                    phase_type: phase[:type] || phase[:phase_type] || phase["type"] || phase["phaseType"],
                    label: phase[:label] || phase["label"],
                    events: Array(phase[:events] || phase["events"]),
                    actions: deep_stringify(Array(phase[:actions] || phase["actions"]))
                  }
                end
              }
            end
          }
        end
      end

      def replace_rounds!(battle, rounds_payload)
        battle.battle_rounds.destroy_all
        rounds_payload.each do |round_payload|
          battle_round = battle.battle_rounds.create!(
            number: round_payload.fetch(:number),
            events: round_payload.fetch(:events)
          )
          round_payload.fetch(:turns).each do |turn_payload|
            battle_turn = battle_round.battle_turns.create!(
              position: turn_payload.fetch(:position),
              player_id: turn_payload.fetch(:player_id),
              player_name: turn_payload.fetch(:player_name)
            )
            turn_payload.fetch(:phases).each do |phase_payload|
              battle_turn.battle_phases.create!(
                position: phase_payload.fetch(:position),
                phase_type: phase_payload.fetch(:phase_type),
                label: phase_payload.fetch(:label),
                events: phase_payload.fetch(:events),
                actions: phase_payload.fetch(:actions, [])
              )
            end
          end
        end
      end

      def deep_stringify(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), memo|
            camel = key.to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase }
            memo[camel] = deep_stringify(nested)
          end
        when Array
          value.map { |entry| deep_stringify(entry) }
        else
          value
        end
      end
    end
  end
end
