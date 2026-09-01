module Balance
  module Dashboard
    module_function

    def build(catalog_version_id: nil, matchup_type: "all")
      version = resolve_version(catalog_version_id)
      scoped_type = normalize_matchup_type(matchup_type)
      counters = load_counters(version.id, scoped_type)
      battles = BalanceBattleRollup.where(catalog_version_id: version.id)
      battles = battles.where(matchup_type: scoped_type) unless scoped_type == "all"

      {
        catalog_versions: catalog_versions_payload,
        selected_version_id: version.id,
        matchup_type: scoped_type,
        summary: summary_payload(counters, battles.count),
        faction_wins: faction_wins(counters),
        faction_matchups: faction_matchups(battles),
        template_wins: template_wins(counters),
        unit_matchups: unit_matchups(counters),
        rule_triggers: bucket_rows(counters, "rule_trigger"),
        rule_results: bucket_rows(counters, "rule_result"),
        action_counts: bucket_rows(counters, "action_count"),
        damage_matrix: damage_matrix_rows(counters),
        morale: bucket_rows(counters, "morale"),
        contacts: bucket_rows(counters, "contact"),
        spells: spell_rows(counters),
        models_lost: bucket_rows(counters, "models_lost"),
        recent_battles: recent_battles(battles),
        simulation_runs: simulation_runs_payload,
        active_simulations: active_simulations_payload,
        active_simulation: active_simulation_payload,
        factions: faction_slugs,
        units: unit_template_keys
      }
    end

    def faction_slugs
      Faction.order(:position).pluck(:slug)
    end

    def unit_template_keys
      Balance::DuelMatrix.unit_template_keys
    end

    def active_simulations_payload
      BalanceSimulationRun.active.order(created_at: :desc).includes(:catalog_version).map { |run| serialize_run(run) }
    end

    def active_simulation_payload
      active_simulations_payload.first
    end

    def simulation_runs_payload
      runs = BalanceSimulationRun.recent.limit(5).includes(:catalog_version).to_a
      recorded = BalanceBattleRollup.where(balance_simulation_run_id: runs.map(&:id))
        .group(:balance_simulation_run_id).count
      runs.map { |run| serialize_run(run, battles_recorded: recorded[run.id].to_i) }
    end

    def catalog_version_payload(version)
      {
        id: version.id,
        content_hash: version.content_hash,
        catalog_hash: version.catalog_hash
      }
    end

    def serialize_run(run, battles_recorded: nil)
      {
        id: run.id,
        status: run.status,
        catalog_version_id: run.catalog_version_id,
        catalog_version: catalog_version_payload(run.catalog_version),
        battles_completed: run.battles_completed,
        battles_failed: run.battles_failed,
        battles_recorded: battles_recorded.nil? ? run.balance_battle_rollups.count : battles_recorded,
        battle_limit: run.battle_limit,
        config: run.config,
        error_message: run.error_message,
        started_at: run.started_at,
        finished_at: run.finished_at,
        created_at: run.created_at
      }
    end

    def resolve_version(catalog_version_id)
      return CatalogVersion.order(id: :desc).first! if catalog_version_id.blank?

      CatalogVersion.find(catalog_version_id)
    end

    def normalize_matchup_type(matchup_type)
      value = matchup_type.to_s
      return "all" unless %w[pvp pvb bvb all].include?(value)

      value
    end

    def catalog_versions_payload
      counts = BalanceBattleRollup.group(:catalog_version_id).count
      CatalogVersion.order(id: :desc).map do |version|
        {
          id: version.id,
          content_hash: version.content_hash,
          catalog_hash: version.catalog_hash,
          rules_hash: version.rules_hash,
          created_at: version.created_at,
          battle_count: counts[version.id].to_i
        }
      end
    end

    def load_counters(catalog_version_id, matchup_type)
      BalanceCounter.where(catalog_version_id: catalog_version_id, matchup_type: matchup_type)
    end

    def summary_payload(counters, battle_count)
      battles = counter_value(counters, "battle", "total")
      upsets = counter_value(counters, "upset", "lower_cost_wins")
      rounds = counter_value(counters, "rounds", "total", field: :sum)

      {
        battle_count: battle_count,
        recorded_battles: battles,
        upset_count: upsets,
        upset_rate: rate(upsets, battles),
        avg_rounds: average(rounds, battles)
      }
    end

    def faction_wins(counters)
      rows = counters.where(bucket: "faction_win").index_by(&:key)
      total = rows.values.sum(&:n)
      faction_slugs.map do |slug|
        wins = rows[slug]&.n.to_i
        {
          faction_id: slug,
          wins: wins,
          winrate: rate(wins, total)
        }
      end.sort_by { |row| -row[:wins] }
    end

    def faction_matchups(battles_scope)
      pairs = Hash.new { |memo, key| memo[key] = { battles: 0, wins: Hash.new(0), left_faction: nil, right_faction: nil } }

      battles_scope.find_each do |rollup|
        metrics = rollup.metrics.deep_symbolize_keys
        left = metrics[:left_faction].to_s
        right = metrics[:right_faction].to_s
        winner = metrics[:winner_faction].to_s
        next if left.blank? || right.blank?

        sorted = [ left, right ].sort
        key = sorted.join(" vs ")
        bucket = pairs[key]
        bucket[:left_faction] ||= sorted[0]
        bucket[:right_faction] ||= sorted[1]
        bucket[:battles] += 1
        bucket[:wins][winner] += 1 if winner.present?
      end

      pairs.map do |key, bucket|
        left_faction = bucket[:left_faction]
        right_faction = bucket[:right_faction]
        left_wins = bucket[:wins][left_faction].to_i
        right_wins = bucket[:wins][right_faction].to_i
        {
          key: key,
          battles: bucket[:battles],
          left_faction: left_faction,
          right_faction: right_faction,
          left_wins: left_wins,
          right_wins: right_wins,
          left_winrate: rate(left_wins, bucket[:battles]),
          right_winrate: rate(right_wins, bucket[:battles])
        }
      end.sort_by { |row| -row[:battles] }
    end

    def template_wins(counters)
      rows = counters.where(bucket: "template_win").index_by(&:key)
      total = rows.values.sum(&:n)
      unit_template_keys.map do |template_id|
        wins = rows[template_id]&.n.to_i
        {
          template_id: template_id,
          wins: wins,
          winrate: rate(wins, total)
        }
      end.sort_by { |row| -row[:wins] }
    end

    def unit_matchups(counters)
      counters.where(bucket: "damage").each_with_object({}) do |row, memo|
        attacker, rest = row.key.split("->", 2)
        target = rest.to_s.split(":", 2).first
        next if attacker.blank? || target.blank?

        key = "#{attacker}->#{target}"
        bucket = memo[key] ||= { attacker: attacker, target: target, hits: 0, total_damage: 0 }
        bucket[:hits] += row.n
        bucket[:total_damage] += row.sum
      end.values.sort_by { |row| -row[:total_damage] }.map do |row|
        row.merge(avg_damage: average(row[:total_damage], row[:hits]))
      end
    end

    def bucket_rows(counters, bucket)
      counters.where(bucket: bucket).order(n: :desc).map do |row|
        { key: row.key, count: row.n, sum: row.sum }
      end
    end

    def damage_matrix_rows(counters)
      counters.where(bucket: "damage").order(sum: :desc).map do |row|
        attacker, rest = row.key.split("->", 2)
        phase = rest.to_s.split(":", 2).last
        target = rest.to_s.split(":", 2).first
        {
          attacker: attacker,
          target: target,
          phase: phase,
          hits: row.n,
          total_damage: row.sum,
          avg_damage: average(row.sum, row.n)
        }
      end
    end

    def spell_rows(counters)
      casts = counters.where(bucket: "spell_cast").index_by(&:key)
      damage = counters.where(bucket: "spell_damage").index_by(&:key)
      keys = (casts.keys + damage.keys).uniq.sort
      keys.map do |key|
        cast_row = casts[key]
        damage_row = damage[key]
        {
          spell_key: key,
          casts: cast_row&.n.to_i,
          total_damage: damage_row&.sum.to_i,
          avg_damage: average(damage_row&.sum.to_i, cast_row&.n.to_i)
        }
      end.sort_by { |row| -row[:casts] }
    end

    def recent_battles(scope)
      scope.includes(:round_matchup, :balance_simulation_run).order(created_at: :desc).limit(20).map do |rollup|
        metrics = rollup.metrics.deep_symbolize_keys
        {
          id: rollup.id,
          created_at: rollup.created_at,
          round_number: rollup.round_matchup&.campaign_round,
          matchup_type: rollup.matchup_type,
          winner_faction: metrics[:winner_faction],
          left_faction: metrics[:left_faction],
          right_faction: metrics[:right_faction],
          rounds: metrics[:rounds],
          upset: metrics[:upset],
          left_army_cost: metrics[:left_army_cost],
          source: rollup.source,
          simulation_run_id: rollup.balance_simulation_run&.id
        }
      end
    end

    def counter_value(counters, bucket, key, field: :n)
      counters.find_by(bucket: bucket, key: key)&.public_send(field).to_i
    end

    def rate(numerator, denominator)
      return 0.0 if denominator.to_i <= 0

      (numerator.to_f / denominator).round(4)
    end

    def average(sum, count)
      return 0.0 if count.to_i <= 0

      (sum.to_f / count).round(2)
    end
  end
end
