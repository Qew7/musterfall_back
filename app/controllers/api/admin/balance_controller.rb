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

      def units
        if CatalogVersion.none?
          return render json: empty_units_payload
        end

        render json: Balance::DuelDashboard.build(
          catalog_version_id: params[:catalog_version_id],
          contact: params[:contact],
          deploy: params[:deploy]
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

      def stop_all_simulations
        runs = Balance::Simulation.stop_all!
        render json: { runs: runs.map { |run| Balance::Dashboard.serialize_run(run) } }
      end

      def run_duel
        catalog = Sim::Catalog::Loader.load
        rng = Sim::Rng::Seeded.new(SecureRandom.random_number(0x7FFFFFFF))
        config = duel_params
        result = Balance::Synthetic::Duel.run!(
          catalog: catalog,
          config: config,
          rng: rng
        )
        version = CatalogVersion.current!
        run = Balance::Duel::Persist.call!(result: result, config: config, catalog_version: version)
        render json: result.merge(duel_run_id: run.id)
      rescue ArgumentError => error
        render json: { error: error.message }, status: :unprocessable_entity
      end

      def start_duel_matrix
        run = Balance::DuelMatrix.start!(config: duel_matrix_params)
        render json: { run: Balance::DuelMatrix.serialize_run(run) }, status: :created
      rescue ArgumentError => error
        render json: { error: error.message }, status: :conflict
      end

      def stop_duel_matrix
        run = Balance::DuelMatrix.stop!(params[:id])
        render json: { run: Balance::DuelMatrix.serialize_run(run) }
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
          :left_template, :right_template, :left_models, :right_models, :contact, :deploy, :iterations
        ).to_h.symbolize_keys.tap do |config|
          raise ArgumentError, "left_template required" if config[:left_template].blank?
          raise ArgumentError, "right_template required" if config[:right_template].blank?
        end
      end

      def duel_matrix_params
        params.permit(:contact, :deploy, :iterations, :batch_size).to_h
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
          active_simulations: [],
          active_simulation: nil,
          factions: Faction.order(:position).pluck(:slug)
        }
      end

      def empty_units_payload
        {
          catalog_versions: [],
          selected_version_id: nil,
          summary: { duel_run_count: 0, total_iterations: 0, avg_rounds: 0 },
          template_wins: [],
          matchups: [],
          recent_runs: [],
          active_duel_matrix: nil,
          duel_matrix_runs: []
        }
      end
    end
  end
end
