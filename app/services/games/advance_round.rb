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
      base_seed = @game.rng_seed.to_i + campaign.version + 17

      # 1) Prepare + pair (short transaction). Matchups must be committed before async jobs.
      planned = nil
      ActiveRecord::Base.transaction do
        prepared = Sim::Campaign::PrepareRound.call(campaign: campaign, catalog: catalog, rng: Sim::Rng::Seeded.new(base_seed))
        return prepared if prepared.failure?

        prepared_campaign = prepared.value
        persist_snapshot!(prepared_campaign, "pre_round")

        planned = Sim::Campaign::PlanMatchups.call(
          campaign: prepared_campaign,
          catalog: catalog,
          rng_seed: base_seed
        )
        return planned if planned.failure?

        replace_matchups!(prepared_campaign.round, planned.value[:matchups])
      end

      plan_payload = planned.value
      matchup_records = @game.round_matchups.for_round(@game, plan_payload[:campaign].round).order(:position).to_a

      # 2) Simulate battles (inline or Solid Queue workers) outside the pairing transaction.
      finished = Games::BattleJobRunner.run_all!(matchup_records)
      if finished.any?(&:failed?)
        return Sim::Result.failure(finished.find(&:failed?).error_message || "battle simulation failed")
      end

      battles = finished.map do |matchup|
        matchup.battle_result.merge(matchup_id: matchup.id, seed: matchup.seed)
      end

      # 3) Settle campaign + persist reports.
      ActiveRecord::Base.transaction do
        settled = Sim::Campaign::SettleMatchups.call(
          campaign: plan_payload[:campaign],
          battles: battles,
          byes: plan_payload[:byes],
          rng: Sim::Rng::Seeded.new(base_seed + 91)
        )
        return settled if settled.failure?

        payload = settled.value
        next_campaign = payload[:campaign]
        next_campaign.version = campaign.version + 1
        repository.replace!(@game, next_campaign)

        persisted = Array(payload[:battles]).map do |battle|
          Sim::Persistence::BattleWriter.persist!(@game, battle, round_number: plan_payload[:campaign].round)
        end

        finished.each { |matchup| Balance::Record.from_matchup!(matchup) }

        persist_snapshot!(next_campaign, "post_round")
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

    def replace_matchups!(campaign_round, matchups)
      @game.round_matchups.where(campaign_round: campaign_round).delete_all

      Array(matchups).each do |matchup|
        @game.round_matchups.create!(
          campaign_round: campaign_round,
          position: matchup[:position],
          seed: matchup[:seed],
          attacker_player_key: matchup[:attacker][:id],
          defender_player_key: matchup[:defender][:id],
          attacker_player_name: matchup[:attacker][:name],
          defender_player_name: matchup[:defender][:name],
          attacker_snapshot: deep_stringify(matchup[:attacker]),
          defender_snapshot: deep_stringify(matchup[:defender]),
          status: "pending",
          result_payload: {}
        )
      end
    end

    def persist_snapshot!(campaign, phase)
      snapshot = @game.round_snapshots.find_or_initialize_by(
        round_number: phase == "post_round" ? campaign.round - 1 : campaign.round,
        phase: phase
      )
      snapshot.payload = { campaign: campaign.to_api_hash }
      snapshot.save!
    end

    def deep_stringify(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, entry), memo|
          memo[key.to_s] = deep_stringify(entry)
        end
      when Array
        value.map { |entry| deep_stringify(entry) }
      else
        value
      end
    end
  end
end
