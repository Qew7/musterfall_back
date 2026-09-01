module Api
  module Admin
    class BalanceController < ApplicationController
      def show
        if CatalogVersion.none?
          return render json: empty_payload
        end

        render json: Balance::Dashboard.build(
          catalog_version_id: params[:catalog_version_id],
          matchup_type: params[:matchup_type]
        )
      end

      def backfill
        Balance::Runner.enqueue_backfill!
        render json: { status: "started" }
      end

      def start_simulation
        run = Balance::Simulation.start!(config: simulation_params)
        render json: { run: Balance::Dashboard.serialize_run(run) }, status: :created
      rescue ArgumentError => error
        render json: { error: error.message }, status: :conflict
      end

      def stop_simulation
        run = Balance::Simulation.stop!(params[:id])
        render json: { run: Balance::Dashboard.serialize_run(run) }
      end

      def run_duel
        catalog = Sim::Catalog::Loader.load
        rng = Sim::Rng::Seeded.new(SecureRandom.random_number(0x7FFFFFFF))
        result = Balance::Synthetic::Duel.run!(
          catalog: catalog,
          config: duel_params,
          rng: rng
        )
        render json: result
      rescue ArgumentError => error
        render json: { error: error.message }, status: :unprocessable_entity
      end

      private

      def simulation_params
        params.permit(
          :battle_limit, :round, :budget_mode, :target_points, :points_jitter,
          :hero_level, :randomize_hero_level, :faction_left, :faction_right, :recruit_strategy,
          :preset
        ).to_h
      end

      def duel_params
        params.permit(
          :left_template, :right_template, :left_models, :right_models, :contact, :iterations
        ).to_h.symbolize_keys.tap do |config|
          raise ArgumentError, "left_template required" if config[:left_template].blank?
          raise ArgumentError, "right_template required" if config[:right_template].blank?
        end
      end

      def empty_payload
        {
          catalog_versions: [],
          selected_version_id: nil,
          matchup_type: params[:matchup_type].presence || "all",
          summary: { battle_count: 0, recorded_battles: 0, upset_count: 0, upset_rate: 0, avg_rounds: 0 },
          faction_wins: [],
          faction_matchups: [],
          rule_triggers: [],
          rule_results: [],
          action_counts: [],
          unit_matchups: [],
          damage_matrix: [],
          morale: [],
          contacts: [],
          spells: [],
          models_lost: [],
          template_wins: [],
          unit_matchups: [],
          recent_battles: [],
          simulation_runs: [],
          active_simulation: nil,
          factions: Faction.order(:position).pluck(:slug)
        }
      end
    end
  end
end
