module Balance
  module Rollup
    DAMAGE_TYPES = %w[melee shooting magic].freeze

    module_function

    def build(result:, attacker:, defender:, catalog_version_id:, round_matchup_id: nil, game_id: nil, source: "campaign")
      report = deep_symbolize(result)
      attacker = deep_symbolize(attacker)
      defender = deep_symbolize(defender)
      actions = Sim::Battle::SemanticSnapshot.extract_actions(report)
      template_map = entity_template_map(attacker, defender)

      left_faction = faction_id(attacker)
      right_faction = faction_id(defender)
      left_bot = bot?(attacker)
      right_bot = bot?(defender)
      matchup_type = matchup_type_for(left_bot, right_bot)

      left_player_id = report.dig(:left, :player_id) || attacker[:id]
      winner_id = report[:winner_id]
      winner_faction = winner_id == left_player_id ? left_faction : right_faction
      loser_faction = winner_faction == left_faction ? right_faction : left_faction

      left_cost = army_cost(attacker)
      right_cost = army_cost(defender)
      winner_cost = winner_id == left_player_id ? left_cost : right_cost
      loser_cost = winner_id == left_player_id ? right_cost : left_cost

      semantic = Sim::Battle::SemanticSnapshot.build(report)
      metrics = {
        catalog_version_id: catalog_version_id,
        round_matchup_id: round_matchup_id,
        game_id: game_id,
        matchup_type: matchup_type,
        source: source,
        winner_id: winner_id,
        rounds: semantic[:rounds],
        winner_faction: winner_faction,
        loser_faction: loser_faction,
        left_faction: left_faction,
        right_faction: right_faction,
        left_bot: left_bot,
        right_bot: right_bot,
        left_army_cost: left_cost,
        right_army_cost: right_cost,
        upset: winner_cost < loser_cost,
        side_health: semantic[:side_health],
        action_counts: semantic[:action_counts],
        rule_triggers: semantic[:rule_effects],
        rule_results: rule_results(actions),
        damage_matrix: damage_matrix(actions, template_map),
        models_lost: models_lost(report, template_map),
        morale_checks: morale_checks(actions),
        contacts: contact_counts(actions),
        spells: spell_stats(actions),
        roster_left: roster_templates(attacker),
        roster_right: roster_templates(defender),
        winning_roster: winning_roster(winner_id, left_player_id, attacker, defender)
      }.compact

      {
        metrics: metrics,
        counters: counter_rows(metrics, matchup_type)
      }
    end

    def entity_template_map(attacker, defender)
      roster_templates_map(attacker).merge(roster_templates_map(defender))
    end

    def roster_templates_map(player)
      Array(player[:roster]).each_with_object({}) do |entry, memo|
        entity_id = entry[:id] || entry["id"]
        template_id = entry[:template_id] || entry["template_id"]
        memo[entity_id.to_s] = template_id.to_s if entity_id && template_id
      end
    end

    def roster_templates(player)
      Array(player[:roster]).filter_map { |entry| entry[:template_id] || entry["template_id"] }.map(&:to_s).sort
    end

    def winning_roster(winner_id, left_player_id, attacker, defender)
      winner_id == left_player_id ? roster_templates(attacker) : roster_templates(defender)
    end

    def faction_id(player)
      player[:faction_id] || player["faction_id"] ||
        player.dig(:faction, :id) || player.dig("faction", "id")
    end

    def bot?(player)
      value = player[:is_bot]
      value = player["is_bot"] if value.nil?
      !!value
    end

    def matchup_type_for(left_bot, right_bot)
      return "bvb" if left_bot && right_bot
      return "pvp" if !left_bot && !right_bot

      "pvb"
    end

    def army_cost(player)
      Array(player[:roster]).sum do |entry|
        entry.dig(:components, :economy, :cost).to_i
      end
    end

    def rule_results(actions)
      actions.flat_map do |action|
        trace = action[:trace] || {}
        rule_keys = Array(trace[:rule_keys]).map { |key| key.to_s.underscore }
        result = trace[:result].to_s
        next [] if result.blank?

        if rule_keys.empty?
          [ result ]
        else
          rule_keys.map { |key| "#{key}:#{result}" }
        end
      end.tally.sort.to_h
    end

    def damage_matrix(actions, template_map)
      actions.each_with_object({}) do |action, memo|
        damage = action[:damage].to_i
        next if damage <= 0

        type = action[:type].to_s
        next unless DAMAGE_TYPES.include?(type)

        actor_template = template_map[action[:actor_id].to_s]
        target_id = action[:target_id] || action.dig(:maneuver, :target_id)
        target_template = template_map[target_id.to_s]
        next if actor_template.blank? || target_template.blank?

        key = "#{actor_template}->#{target_template}"
        bucket = memo[key] ||= { "melee" => 0, "shooting" => 0, "magic" => 0, "hits" => 0, "total" => 0 }
        bucket[type] += damage
        bucket["hits"] += 1
        bucket["total"] += damage
      end
    end

    def models_lost(report, template_map)
      sides = [ report[:left], report[:right] ].compact
      sides.each_with_object({}) do |side, memo|
        Array(side[:combatants]).each do |combatant|
          template_id = template_map[combatant[:entity_id].to_s]
          next if template_id.blank?

          starting = (combatant[:starting_models] || combatant[:models_remaining]).to_i
          remaining = combatant[:models_remaining].to_i
          remaining = 0 if combatant[:current_health].to_i <= 0
          lost = [ starting - remaining, 0 ].max
          next if lost <= 0

          memo[template_id] = memo.fetch(template_id, 0) + lost
        end
      end
    end

    def morale_checks(actions)
      actions.each_with_object({ "passed" => 0, "failed" => 0, "routed" => 0, "rallied" => 0 }) do |action, memo|
        type = action[:type].to_s
        next unless type == "morale" || type == "fear_check"

        result = action.dig(:trace, :result).to_s
        check = action[:check] || action[:morale] || {}
        if result == "routed"
          memo["routed"] += 1
        elsif result == "rallied"
          memo["rallied"] += 1
        elsif check[:passed] == false
          memo["failed"] += 1
        elsif check[:passed] == true || result == "passed"
          memo["passed"] += 1
        end
      end
    end

    def contact_counts(actions)
      actions.filter_map { |action| Sim::Battle::SemanticSnapshot.contact_fingerprint(action) }
        .group_by { |entry| [ entry[:slot], entry[:kind] ].compact.join(":").presence || "contact" }
        .transform_values(&:length)
    end

    def spell_stats(actions)
      actions.each_with_object({}) do |action, memo|
        spell_key = action[:spell_key]
        next if spell_key.blank?

        bucket = memo[spell_key.to_s] ||= { "casts" => 0, "damage" => 0, "failed" => 0 }
        bucket["casts"] += 1
        bucket["damage"] += action[:damage].to_i
        bucket["failed"] += 1 if action[:outcome].to_s == "failed"
      end
    end

    def counter_rows(metrics, matchup_type)
      rows = []
      add_counter = lambda do |bucket, key, n: 1, sum: 0, types: [ matchup_type, "all" ]|
        types.each do |type|
          rows << { bucket: bucket, key: key, matchup_type: type, n: n, sum: sum }
        end
      end

      add_counter.call("battle", "total")
      add_counter.call("faction_win", metrics[:winner_faction].to_s) if metrics[:winner_faction].present?
      if metrics[:left_faction].present? && metrics[:right_faction].present?
        key = [ metrics[:left_faction], metrics[:right_faction] ].sort.join(" vs ")
        add_counter.call("faction_matchup", key)
      end
      add_counter.call("upset", "lower_cost_wins") if metrics[:upset]
      add_counter.call("rounds", "total", sum: metrics[:rounds].to_i)

      metrics.fetch(:rule_triggers, {}).each do |key, count|
        add_counter.call("rule_trigger", key.to_s, n: count.to_i)
      end
      metrics.fetch(:rule_results, {}).each do |key, count|
        add_counter.call("rule_result", key.to_s, n: count.to_i)
      end
      metrics.fetch(:action_counts, {}).each do |key, count|
        add_counter.call("action_count", key.to_s, n: count.to_i)
      end
      metrics.fetch(:damage_matrix, {}).each do |pair, stats|
        DAMAGE_TYPES.each do |phase|
          damage = stats[phase].to_i
          next if damage <= 0

          hits = stats["hits"].to_i
          add_counter.call("damage", "#{pair}:#{phase}", n: hits, sum: damage)
        end
      end
      metrics.fetch(:models_lost, {}).each do |template_id, count|
        add_counter.call("models_lost", template_id.to_s, n: count.to_i)
      end
      metrics.fetch(:morale_checks, {}).each do |key, count|
        add_counter.call("morale", key.to_s, n: count.to_i) if count.to_i.positive?
      end
      metrics.fetch(:contacts, {}).each do |key, count|
        add_counter.call("contact", key.to_s, n: count.to_i)
      end
      metrics.fetch(:spells, {}).each do |spell_key, stats|
        add_counter.call("spell_cast", spell_key.to_s, n: stats["casts"].to_i)
        add_counter.call("spell_damage", spell_key.to_s, n: stats["casts"].to_i, sum: stats["damage"].to_i)
      end
      metrics.fetch(:winning_roster, []).each do |template_id|
        add_counter.call("template_win", template_id.to_s)
      end

      rows
    end

    def deep_symbolize(value)
      Sim::Campaign::State.deep_symbolize(value || {})
    end
  end
end
