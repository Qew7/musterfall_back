module Sim
  module Campaign
    class AdvanceRound
      def self.call(campaign:, catalog:, rng:)
        new(campaign, catalog, rng).call
      end

      def initialize(campaign, catalog, rng)
        @campaign = campaign.deep_dup
        @catalog = catalog
        @rng = rng
      end

      def call
        active_players = @campaign.players.select { |player| player[:status] == "active" }
        return Result.ok(@campaign) if active_players.length <= 1

        active_players.each { |player| ensure_deployment!(player) }

        report = { round: @campaign.round, matchups: [], byes: [] }
        queue = active_players.dup

        while queue.length > 1
          attacker = queue.shift
          defender = queue.shift
          battle = Battle::Simulator.call(attacker, defender, @catalog, rng: @rng)
          report[:matchups] << battle

          loser_id = battle[:winner_id] == attacker[:id] ? defender[:id] : attacker[:id]
          winner = @campaign.find_player(battle[:winner_id])
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

        if queue.length == 1
          bye_player = queue.first
          bye_player[:treasury] += Constants::BYE_REWARD
          bye_player[:round_notes] = [ "Раунд #{@campaign.round}: свободный проход, +#{Constants::BYE_REWARD} припасов" ]
          report[:byes] << { player_id: bye_player[:id], player_name: bye_player[:name] }
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

      def ensure_deployment!(player)
        deployable = player[:roster].select { |entry| entry.dig(:state, :current_health).to_i > 0 }
        visible = deployable.select do |entry|
          Entities::Footprint.deployable?(entry) || (entry[:kind] == "hero" && entry[:state][:attached_to])
        end
        return if visible.any?

        result = Deploy.call(campaign: @campaign, player_id: player[:id], action: "auto")
        @campaign = result.value if result.ok?
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
