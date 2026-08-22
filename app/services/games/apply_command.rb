module Games
  class ApplyCommand
    COMMANDS = {
      assign_faction: ->(campaign, catalog, rng, params) {
        Sim::Campaign::AssignFaction.call(
          campaign: campaign,
          catalog: catalog,
          player_id: params.fetch(:player_id),
          faction_id: params.fetch(:faction_id),
          rng: rng,
          school_key: params[:school_key],
          template_id: params[:template_id]
        )
      },
      recruit: ->(campaign, catalog, rng, params) {
        Sim::Campaign::Recruit.call(
          campaign: campaign,
          catalog: catalog,
          player_id: params.fetch(:player_id),
          template_id: params.fetch(:template_id),
          rng: rng,
          school_key: params[:school_key]
        )
      },
      dismiss: ->(campaign, _catalog, _rng, params) {
        Sim::Campaign::Dismiss.call(
          campaign: campaign,
          player_id: params.fetch(:player_id),
          entity_id: params.fetch(:entity_id)
        )
      },
      attach_hero: ->(campaign, _catalog, _rng, params) {
        Sim::Campaign::AttachHero.call(
          campaign: campaign,
          player_id: params.fetch(:player_id),
          hero_id: params.fetch(:hero_id),
          unit_id: params.fetch(:unit_id)
        )
      },
      deploy: ->(campaign, _catalog, _rng, params) {
        Sim::Campaign::Deploy.call(
          campaign: campaign,
          player_id: params.fetch(:player_id),
          action: params.fetch(:deploy_mode),
          entity_id: params[:entity_id],
          x: params[:x],
          y: params[:y],
          facing: params[:facing],
          direction: params[:direction]
        )
      },
      prepare_hero_draft: ->(campaign, catalog, rng, params) {
        Sim::Campaign::HeroDraft.prepare(
          campaign: campaign,
          catalog: catalog,
          player_id: params.fetch(:player_id),
          hero_id: params.fetch(:hero_id),
          rng: rng
        )
      },
      pick_hero_draft: ->(campaign, _catalog, _rng, params) {
        Sim::Campaign::HeroDraft.pick(
          campaign: campaign,
          player_id: params.fetch(:player_id),
          hero_id: params.fetch(:hero_id),
          upgrade_id: params.fetch(:upgrade_id)
        )
      },
      upgrade_access: ->(campaign, _catalog, _rng, params) {
        Sim::Campaign::UpgradeAccess.call(
          campaign: campaign,
          player_id: params.fetch(:player_id)
        )
      },
      restore_unit: ->(campaign, catalog, _rng, params) {
        Sim::Campaign::RestoreUnit.call(
          campaign: campaign,
          catalog: catalog,
          player_id: params.fetch(:player_id),
          entity_id: params.fetch(:entity_id),
          models: params[:models]
        )
      },
      prepare_round: ->(campaign, catalog, rng, _params) {
        Sim::Campaign::PrepareRound.call(campaign: campaign, catalog: catalog, rng: rng)
      }
    }.freeze

    def self.call(game:, command:, base_version:, params: {})
      new(game, command, base_version, params).call
    end

    def initialize(game, command, base_version, params)
      @game = game
      @command = command.to_sym
      @base_version = base_version.to_i
      @params = params.to_h.symbolize_keys
    end

    def call
      return Sim::Result.failure("unknown command") unless COMMANDS.key?(@command)
      return Sim::Result.failure("game is finished") if @game.status == "finished"

      repository = Sim::Persistence::CampaignRepository.new
      campaign = repository.load(@game)
      if @base_version != campaign.version
        return Sim::Result.failure("version conflict", code: :conflict)
      end

      catalog = Sim::Catalog::Loader.load
      rng = Sim::Rng::Seeded.new(@game.rng_seed.to_i + campaign.version + 1)
      result = COMMANDS[@command].call(campaign, catalog, rng, @params)
      return result if result.failure?

      next_campaign = result.value
      next_campaign.version = campaign.version + 1
      repository.replace!(@game, next_campaign)
      @game.reload
      Sim::Result.ok(game: @game, campaign: next_campaign)
    end
  end
end
