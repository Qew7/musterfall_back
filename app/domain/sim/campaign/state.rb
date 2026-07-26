module Sim
  module Campaign
    class State
      attr_accessor :round, :winner_id, :last_round_report, :players, :id_sequence, :version

      def initialize(round:, winner_id: nil, last_round_report: nil, players:, id_sequence: 0, version: 0)
        @round = round
        @winner_id = winner_id
        @last_round_report = last_round_report
        @players = players
        @id_sequence = id_sequence
        @version = version
      end

      def deep_dup
        Marshal.load(Marshal.dump(self))
      end

      def find_player(player_id)
        players.find { |player| player[:id] == player_id }
      end

      def find_entity(player_id, entity_id)
        find_player(player_id)&.dig(:roster)&.find { |entity| entity[:id] == entity_id }
      end

      def to_api_hash
        {
          round: round,
          winnerId: winner_id,
          lastRoundReport: camelize_report(last_round_report),
          players: players.map { |player| serialize_player(player) }
        }
      end

      def self.from_api_hash(payload, version: 0)
        players = Array(payload["players"] || payload[:players]).map { |player| deep_symbolize(player) }
        new(
          round: (payload["round"] || payload[:round] || 1).to_i,
          winner_id: payload["winnerId"] || payload[:winner_id] || payload[:winnerId],
          last_round_report: deep_symbolize(payload["lastRoundReport"] || payload[:last_round_report] || payload[:lastRoundReport]),
          players: players.map { |player| normalize_player(player) },
          id_sequence: infer_id_sequence(players),
          version: version
        )
      end

      def self.normalize_player(player)
        player = player.transform_keys(&:to_sym)
        player[:roster] = Array(player[:roster]).map { |entity| normalize_entity(entity) }
        player[:round_notes] = Array(player[:round_notes] || player[:roundNotes])
        player[:is_bot] = player.key?(:is_bot) ? player[:is_bot] : player[:isBot]
        player[:faction_id] = player[:faction_id] || player[:factionId]
        player
      end

      def self.normalize_entity(entity)
        entity = deep_symbolize(entity)
        entity[:components] = deep_symbolize(entity[:components] || {})
        entity[:state] = deep_symbolize(entity[:state] || {})
        entity
      end

      def self.infer_id_sequence(players)
        players.flat_map { |player| Array(player[:roster] || player["roster"]) }.map do |entity|
          id = entity[:id] || entity["id"]
          id.to_s[/\d+/].to_i
        end.max.to_i
      end

      def self.deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), memo|
            memo[key.to_s.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym] = deep_symbolize(nested)
          end
        when Array
          value.map { |entry| deep_symbolize(entry) }
        else
          value
        end
      end

      private

      def serialize_player(player)
        {
          id: player[:id],
          name: player[:name],
          isBot: player[:is_bot],
          status: player[:status],
          factionId: player[:faction_id],
          treasury: player[:treasury],
          roster: player[:roster].map { |entity| serialize_entity(entity) },
          victories: player[:victories],
          roundNotes: player[:round_notes]
        }
      end

      def serialize_entity(entity)
        components = entity[:components]
        {
          id: entity[:id],
          ownerId: entity[:owner_id],
          templateId: entity[:template_id],
          name: entity[:name],
          kind: entity[:kind],
          components: {
            identity: camelize_keys(components[:identity]),
            combat: camelize_keys(components[:combat]),
            formation: camelize_keys(components[:formation]),
            abilities: components[:abilities],
            health: camelize_keys(components[:health]),
            economy: camelize_keys(components[:economy]),
            progression: components[:progression] ? camelize_keys(components[:progression]) : nil,
            hero: components[:hero] ? camelize_keys(components[:hero]) : nil
          }.compact,
          state: camelize_keys(entity[:state])
        }
      end

      def camelize_keys(hash)
        return nil if hash.nil?

        hash.each_with_object({}) do |(key, value), memo|
          camel = key.to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase }
          memo[camel] = value.is_a?(Hash) ? camelize_keys(value) : value
        end
      end

      def camelize_report(report)
        return nil if report.nil?

        deep_camelize(report)
      end

      def deep_camelize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), memo|
            camel = key.to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase }
            memo[camel] = deep_camelize(nested)
          end
        when Array
          value.map { |entry| deep_camelize(entry) }
        else
          value
        end
      end
    end
  end
end
