module Sim
  module Battle
    # Re-run a stored RoundMatchup with the same RNG + terrain seed (no DB writes).
    class Replay
      def self.call(matchup:, compare: false)
        new(matchup, compare: compare).call
      end

      def self.find_matchup!(battle:)
        matchup = RoundMatchup
          .where(game_id: battle.game_id, campaign_round: battle.round_number)
          .find do |row|
            [ row.attacker_player_key, row.defender_player_key ].sort ==
              [ battle.left_player_id, battle.right_player_id ].sort
          end
        raise ArgumentError, "no RoundMatchup for battle #{battle.id}" unless matchup

        matchup
      end

      def initialize(matchup, compare: false)
        @matchup = matchup
        @compare = compare
      end

      def call
        catalog = Catalog::Loader.load
        map_seed = TerrainMap.map_seed(rng_seed: @matchup.game.rng_seed, round: @matchup.campaign_round)
        fresh = Simulator.call(
          @matchup.attacker_player,
          @matchup.defender_player,
          catalog,
          rng: Rng::Seeded.new(@matchup.seed),
          map_seed: map_seed
        )

        payload = {
          matchup_id: @matchup.id,
          game_id: @matchup.game_id,
          campaign_round: @matchup.campaign_round,
          seed: @matchup.seed,
          map_seed: map_seed,
          attacker: @matchup.attacker_player_name,
          defender: @matchup.defender_player_name,
          result: fresh
        }

        if @compare
          stored = symbolize(@matchup.result_payload)
          payload[:compare] = compare_results(stored, fresh) if stored.present?
        end

        payload
      end

      private

      def compare_results(stored, fresh)
        {
          winner_changed: stored[:winner_id] != fresh[:winner_id],
          stored_winner_id: stored[:winner_id],
          fresh_winner_id: fresh[:winner_id],
          stored_summary: stored[:summary],
          fresh_summary: fresh[:summary],
          movement: diff_movement_actions(stored, fresh),
          identical: stored.deep_stringify_keys == fresh.deep_stringify_keys
        }
      end

      def diff_movement_actions(stored, fresh)
        stored_actions = extract_movement_actions(stored)
        fresh_actions = extract_movement_actions(fresh)
        diffs = []

        max = [ stored_actions.length, fresh_actions.length ].max
        max.times do |index|
          left = stored_actions[index]
          right = fresh_actions[index]
          next if left == right

          diffs << {
            index: index,
            stored: left,
            fresh: right
          }
        end

        {
          stored_count: stored_actions.length,
          fresh_count: fresh_actions.length,
          changed: diffs.any?,
          diffs: diffs.first(50)
        }
      end

      def extract_movement_actions(report)
        symbolize(report).fetch(:rounds, []).flat_map do |round|
          round.fetch(:turns, []).flat_map do |turn|
            turn.fetch(:phases, []).flat_map do |phase|
              phase.fetch(:actions, []).select { |action| action[:type] == :movement }.map do |action|
                {
                  summary: action[:summary],
                  actor_id: action[:actor_id],
                  from: action[:from],
                  to: action[:to],
                  maneuver: compact_maneuver(action[:maneuver]),
                  wheel: action[:wheel],
                  charge: action[:charge]
                }
              end
            end
          end
        end
      end

      def compact_maneuver(maneuver)
        return nil unless maneuver

        maneuver.slice(:kind, :target_id, :contact_slot, :truncated_by_collision, :blocked_by_ally)
      end

      def symbolize(value)
        Sim::Campaign::State.deep_symbolize(value)
      end
    end
  end
end
