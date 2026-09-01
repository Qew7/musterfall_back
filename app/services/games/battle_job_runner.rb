module Games
  # Runs battle simulation jobs according to environment:
  # - inline (test / default development): perform_now in the request
  # - async (production / docker): perform_later via Solid Queue workers
  module BattleJobRunner
    module_function

    def enqueue_all!(matchups)
      ids = Array(matchups).map { |matchup| matchup.is_a?(RoundMatchup) ? matchup.id : matchup }
      ids.each { |id| SimulateBattleJob.perform_later(id) }
      ids
    end

    def run_all!(matchups)
      ids = Array(matchups).map { |matchup| matchup.is_a?(RoundMatchup) ? matchup.id : matchup }
      return [] if ids.empty?

      ids.each { |id| SimulateBattleJob.perform_now(id) }

      RoundMatchup.where(id: ids).order(:position).to_a
    end

    def inline?
      raw = Rails.configuration.x.battle_jobs&.execution_mode
      mode = raw.respond_to?(:to_sym) ? raw.to_sym : :inline
      mode == :inline
    end
  end
end
