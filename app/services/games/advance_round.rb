module Games
  class AdvanceRound
    def self.call(game:, base_version:)
      new(game, base_version).call
    end

    def initialize(game, base_version)
      @game = game
      @base_version = base_version.to_i
    end

    def call
      return Sim::Result.failure("game is finished") if @game.status == "finished"

      repository = Sim::Persistence::CampaignRepository.new
      campaign = repository.load(@game)
      if @base_version != campaign.version
        return Sim::Result.failure("version conflict", code: :conflict)
      end

      catalog = Sim::Catalog::Loader.load
      rng = Sim::Rng::Seeded.new(@game.rng_seed.to_i + campaign.version + 17)

      ActiveRecord::Base.transaction do
        prepared = Sim::Campaign::PrepareRound.call(campaign: campaign, catalog: catalog, rng: rng)
        return prepared if prepared.failure?

        prepared_campaign = prepared.value
        persist_snapshot!(prepared_campaign, "pre_round")

        advanced = Sim::Campaign::AdvanceRound.call(campaign: prepared_campaign, catalog: catalog, rng: rng)
        return advanced if advanced.failure?

        payload = advanced.value
        next_campaign = payload[:campaign]
        next_campaign.version = campaign.version + 1
        repository.replace!(@game, next_campaign)

        battles = Array(payload[:battles]).map do |battle|
          Sim::Persistence::BattleWriter.persist!(@game, battle, round_number: prepared_campaign.round)
        end

        persist_snapshot!(next_campaign, "post_round")
        @game.update!(status: next_campaign.winner_id ? "finished" : "active")
        @game.reload

        Sim::Result.ok(
          game: @game,
          campaign: next_campaign,
          battles: battles,
          meta_reward: payload[:meta_reward]
        )
      end
    end

    private

    def persist_snapshot!(campaign, phase)
      snapshot = @game.round_snapshots.find_or_initialize_by(
        round_number: phase == "post_round" ? campaign.round - 1 : campaign.round,
        phase: phase
      )
      snapshot.payload = { campaign: campaign.to_api_hash }
      snapshot.save!
    end
  end
end
