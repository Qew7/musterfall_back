module Sim
  module Campaign
    # Apply finished battle results + byes onto campaign state.
    class SettleMatchups
      def self.call(campaign:, battles:, byes: [])
        new(campaign, battles, byes).call
      end

      def initialize(campaign, battles, byes)
        @campaign = campaign.deep_dup
        @battles = Array(battles)
        @byes = Array(byes)
      end

      def call
        report = { round: @campaign.round, matchups: [], byes: [] }

        @battles.each do |battle|
          report[:matchups] << battle

          attacker_id = battle.dig(:left, :player_id) || battle[:left_player_id]
          defender_id = battle.dig(:right, :player_id) || battle[:right_player_id]
          winner_id = battle[:winner_id]
          loser_id = winner_id == attacker_id ? defender_id : attacker_id

          winner = @campaign.find_player(winner_id)
          loser = @campaign.find_player(loser_id)

          if winner
            winner[:treasury] += Constants::WIN_REWARD
            winner[:victories] += 1
            winner[:round_notes] = [ "Победа в раунде #{@campaign.round}: +#{Constants::WIN_REWARD} припасов" ]
          end

          if loser
            loser[:status] = "eliminated"
            loser[:round_notes] = [ "Разбит в раунде #{@campaign.round}" ]
          end
        end

        @byes.each do |bye|
          bye_player = @campaign.find_player(bye[:player_id] || bye["player_id"])
          next unless bye_player

          bye_player[:treasury] += Constants::BYE_REWARD
          bye_player[:round_notes] = [ "Раунд #{@campaign.round}: свободный проход, +#{Constants::BYE_REWARD} припасов" ]
          report[:byes] << {
            player_id: bye_player[:id],
            player_name: bye_player[:name]
          }
        end

        survivors = @campaign.players.select { |player| player[:status] == "active" }
        @campaign.winner_id = survivors.first[:id] if survivors.length == 1
        @campaign.last_round_report = report
        @campaign.round += 1

        Result.ok(
          campaign: @campaign,
          battles: report[:matchups],
          meta_reward: meta_reward(@campaign)
        )
      end

      private

      def meta_reward(campaign)
        return nil unless campaign.winner_id

        winner = campaign.find_player(campaign.winner_id)
        return nil unless winner

        {
          player_id: winner[:id],
          player_name: winner[:name],
          faction_id: winner[:faction_id],
          experience: 25 + (winner[:victories] * 5),
          essence: 3 + winner[:victories]
        }
      end
    end
  end
end
