module Sim
  module Campaign
    # Apply finished battle results + byes onto campaign state.
    class SettleMatchups
      def self.call(campaign:, battles:, byes: [], rng: Rng::Seeded.new(0))
        new(campaign, battles, byes, rng).call
      end

      def initialize(campaign, battles, byes, rng)
        @campaign = campaign.deep_dup
        @battles = Array(battles)
        @byes = Array(byes)
        @rng = rng
      end

      def call
        report = { round: @campaign.round, matchups: [], byes: [] }

        BattleAftermath.apply!(campaign: @campaign, battles: @battles, rng: @rng)

        @battles.each do |battle|
          report[:matchups] << battle

          attacker_id = battle.dig(:left, :player_id) || battle[:left_player_id]
          defender_id = battle.dig(:right, :player_id) || battle[:right_player_id]
          winner_id = battle[:winner_id]
          loser_id = winner_id == attacker_id ? defender_id : attacker_id

          winner = @campaign.find_player(winner_id)
          loser = @campaign.find_player(loser_id)

          if winner
            winner[:victories] += 1
            winner[:round_notes] = [ "Победа в раунде #{@campaign.round}" ]
            Upgrades::Draft.grant_battle_credit!(winner, Upgrades::Draft::WIN_CREDIT)
          end

          if loser
            loser[:round_notes] = [ "Поражение в раунде #{@campaign.round}" ]
            Upgrades::Draft.grant_battle_credit!(loser, Upgrades::Draft::LOSS_CREDIT)
          end
        end

        @byes.each do |bye|
          bye_player = @campaign.find_player(bye[:player_id] || bye["player_id"])
          next unless bye_player

          bye_player[:round_notes] = [ "Раунд #{@campaign.round}: свободный проход" ]
          report[:byes] << {
            player_id: bye_player[:id],
            player_name: bye_player[:name]
          }
        end

        @campaign.round += 1
        grant_round_income!
        crown_winner_if_finished!

        @campaign.last_round_report = report
        Result.ok(
          campaign: @campaign,
          battles: report[:matchups],
          meta_reward: meta_reward(@campaign)
        )
      end

      private

      def grant_round_income!
        return if @campaign.winner_id

        amount = Constants.income_for(@campaign.round)
        @campaign.players.each do |player|
          next unless player[:status] == "active"

          player[:treasury] = amount
          notes = Array(player[:round_notes])
          notes << "Припасы раунда #{@campaign.round}: #{amount}"
          player[:round_notes] = notes
        end
      end

      def crown_winner_if_finished!
        return if @campaign.round <= Constants::MAX_CAMPAIGN_ROUNDS

        active = @campaign.players.select { |player| player[:status] == "active" }
        best = active.max_by { |player| [ player[:victories].to_i, player[:treasury].to_i ] }
        @campaign.winner_id = best[:id] if best
      end

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
