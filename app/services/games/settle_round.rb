module Games
  class SettleRound
    def self.call(game:, campaign_round:)
      new(game, campaign_round).call
    end

    def self.enqueue_if_ready!(game_id, campaign_round)
      game = Game.find_by(id: game_id)
      return unless game
      return unless game.status == "simulating"

      scope = game.round_matchups.for_round(game, campaign_round)
      return if scope.empty?
      return if scope.where(status: %w[pending running]).exists?

      if scope.where(status: "failed").exists?
        game.update!(status: "active")
        return
      end

      return unless scope.where.not(status: "completed").empty?

      SettleRoundJob.perform_later(game_id, campaign_round)
    end

    def initialize(game, campaign_round)
      @game = game
      @campaign_round = campaign_round.to_i
    end

    def call
      return Sim::Result.failure("game is not simulating") unless @game.status == "simulating"

      snapshot = @game.round_snapshots.find_by(round_number: @campaign_round, phase: "pre_round")
      return Sim::Result.failure("round plan not found") unless snapshot

      plan = snapshot.payload.fetch("roundPlan", {})
      byes = plan["byes"] || []
      base_seed = plan.fetch("baseSeed").to_i

      matchups = @game.round_matchups.for_round(@game, @campaign_round).order(:position).to_a
      if matchups.any?(&:failed?)
        @game.update!(status: "active")
        return Sim::Result.failure(matchups.find(&:failed?).error_message || "battle simulation failed")
      end
      return Sim::Result.failure("battles still running") unless matchups.all?(&:completed?)

      if @game.round_snapshots.exists?(round_number: @campaign_round, phase: "post_round")
        @game.update!(status: @game.winner_player_key ? "finished" : "active")
        return Sim::Result.ok(game: @game.reload)
      end

      repository = Sim::Persistence::CampaignRepository.new
      campaign = repository.load(@game)
      if campaign.version != plan.fetch("campaignVersion").to_i
        return Sim::Result.failure("version conflict", code: :conflict)
      end

      battles = matchups.map do |matchup|
        matchup.battle_result.merge(matchup_id: matchup.id, seed: matchup.seed)
      end

      ActiveRecord::Base.transaction do
        settled = Sim::Campaign::SettleMatchups.call(
          campaign: campaign,
          battles: battles,
          byes: byes,
          rng: Sim::Rng::Seeded.new(base_seed + 91)
        )
        return settled if settled.failure?

        payload = settled.value
        next_campaign = payload[:campaign]
        next_campaign.version = campaign.version + 1
        repository.replace!(@game, next_campaign)

        persisted = Array(payload[:battles]).map do |battle|
          Sim::Persistence::BattleWriter.persist!(@game, battle, round_number: @campaign_round)
        end

        matchups.each { |matchup| Balance::Record.from_matchup!(matchup) }

        persist_snapshot!(@game, next_campaign, "post_round")
        @game.update!(status: next_campaign.winner_id ? "finished" : "active")
        @game.reload

        Sim::Result.ok(
          game: @game,
          campaign: next_campaign,
          battles: persisted,
          meta_reward: payload[:meta_reward]
        )
      end
    end

    private

    def persist_snapshot!(game, campaign, phase)
      snapshot = game.round_snapshots.find_or_initialize_by(
        round_number: phase == "post_round" ? campaign.round - 1 : campaign.round,
        phase: phase
      )
      snapshot.payload = { campaign: campaign.to_api_hash }
      snapshot.save!
    end
  end
end
