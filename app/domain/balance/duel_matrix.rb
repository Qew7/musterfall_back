module Balance
  module DuelMatrix
    DEFAULT_BATCH_SIZE = 10
    MAX_ITERATIONS = Balance::Synthetic::Duel::MAX_ITERATIONS

    module_function

    def start!(config:)
      templates = unit_template_keys
      raise ArgumentError, "need at least 2 unit templates" if templates.length < 2

      normalized = normalize_config(config)
      batches = plan_batches(templates, batch_size: normalized[:batch_size])
      version = CatalogVersion.current!
      run = BalanceDuelMatrixRun.create!(
        catalog_version: version,
        status: "pending",
        config: normalized,
        unit_templates: templates,
        seed: SecureRandom.random_number(0x7FFFFFFF),
        batches_total: batches.length,
        matchups_total: matchup_count(templates.length)
      )

      batches.each do |batch|
        Runner.enqueue_duel_matrix_batch!(
          run.id,
          batch[:batch_index],
          batch[:anchors],
          templates
        )
      end

      run.update!(status: "running", started_at: Time.current)
      run
    end

    def stop!(run_id)
      run = BalanceDuelMatrixRun.find(run_id)
      run.stop!
      Runner.enqueue_duel_matrix_finalize!(run.id) if run.stopping?
      run
    end

    def unit_template_keys
      Unit.order(:template_key).pluck(:template_key)
    end

    def normalize_config(raw)
      config = raw.deep_symbolize_keys
      {
        contact: Balance::Synthetic::Duel.normalize_contact(config[:contact]),
        deploy: Balance::Synthetic::Duel.normalize_deploy(config[:deploy].presence || "ranged"),
        random_first_turn: config.key?(:random_first_turn) ? !!config[:random_first_turn] : true,
        iterations: config[:iterations].to_i.clamp(1, MAX_ITERATIONS),
        batch_size: config[:batch_size].to_i.clamp(1, 50).nonzero? || DEFAULT_BATCH_SIZE
      }
    end

    def plan_batches(templates, batch_size:)
      templates.sort.each_slice(batch_size).map.with_index do |anchors, batch_index|
        { batch_index: batch_index, anchors: anchors }
      end
    end

    def pairs_for_batch(all_templates, anchors)
      index_of = all_templates.each_with_index.to_h
      anchors.flat_map do |anchor|
        idx = index_of.fetch(anchor)
        all_templates[(idx + 1)..].map { |opponent| [ anchor, opponent ] }
      end
    end

    def matchup_count(unit_count)
      unit_count * (unit_count - 1) / 2
    end

    def serialize_run(run)
      {
        id: run.id,
        status: run.status,
        catalog_version_id: run.catalog_version_id,
        catalog_version: Balance::Dashboard.catalog_version_payload(run.catalog_version),
        batches_completed: run.batches_completed,
        batches_total: run.batches_total,
        matchups_completed: run.matchups_completed,
        matchups_total: run.matchups_total,
        matchups_failed: run.matchups_failed,
        unit_count: run.unit_templates.length,
        config: run.config,
        error_message: run.error_message,
        started_at: run.started_at,
        finished_at: run.finished_at,
        created_at: run.created_at
      }
    end
  end
end
