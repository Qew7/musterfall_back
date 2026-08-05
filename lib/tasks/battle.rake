namespace :battle do
  desc "List recent matchups (MATCHUP_LIMIT=10)"
  task list: :environment do
    limit = ENV.fetch("MATCHUP_LIMIT", "10").to_i
    rows = RoundMatchup.includes(:game).order(id: :desc).limit(limit)

    if rows.empty?
      puts "No RoundMatchup rows found."
      next
    end

    rows.each do |matchup|
      stored = matchup.result_payload || {}
      rounds = Array(stored["rounds"] || stored[:rounds])
      puts [
        "id=#{matchup.id}",
        "game=#{matchup.game_id}",
        "round=#{matchup.campaign_round}",
        "seed=#{matchup.seed}",
        "status=#{matchup.status}",
        "#{matchup.attacker_player_name} vs #{matchup.defender_player_name}",
        "rounds=#{rounds.size}"
      ].join(" | ")
    end
  end

  desc "Replay a stored matchup (COMPARE=1 or COMPARE=semantic)"
  task replay: :environment do
    matchup = resolve_matchup!
    compare = ENV["COMPARE"].to_s == "semantic" ? :semantic : ActiveModel::Type::Boolean.new.cast(ENV["COMPARE"])
    payload = Sim::Battle::Replay.call(matchup: matchup, compare: compare)

    out_path = ENV["OUT"].presence || default_replay_path(matchup.id)
    FileUtils.mkdir_p(File.dirname(out_path))
    File.write(out_path, JSON.pretty_generate(deep_stringify(payload)))

    puts "Replayed matchup #{matchup.id} seed=#{matchup.seed} map_seed=#{payload[:map_seed]}"
    puts "Winner: #{payload.dig(:result, :winner_name)} — #{payload.dig(:result, :summary)}"
    puts "Wrote #{out_path}"

    if compare && payload[:compare]
      print_compare(payload[:compare])
    elsif compare
      warn "COMPARE requested but stored result_payload is empty (status=#{matchup.status})"
    end
  end

  desc "Export a RoundMatchup into the checked-in scenario corpus (MATCHUP_ID; OUT optional)"
  task export_scenario: :environment do
    abort "Set MATCHUP_ID" unless ENV["MATCHUP_ID"].present?

    matchup = RoundMatchup.find(ENV["MATCHUP_ID"])
    payload = Sim::Battle::ScenarioCorpus.export(matchup)
    out_path = ENV["OUT"].presence || Rails.root.join(
      "test/fixtures/battle_scenarios/matchup_#{matchup.id}.json"
    ).to_s
    FileUtils.mkdir_p(File.dirname(out_path))
    File.write(out_path, JSON.pretty_generate(deep_stringify(payload)))
    puts "Exported matchup #{matchup.id} to #{out_path}"
  end

  desc "Replay every checked-in battle scenario and report semantic drift"
  task replay_corpus: :environment do
    pattern = Rails.root.join("test/fixtures/battle_scenarios/*.{json,yml,yaml}")
    paths = Dir.glob(pattern).sort
    abort "No battle scenarios found at #{pattern}" if paths.empty?

    failures = []
    paths.each do |path|
      entry = Sim::Battle::ScenarioCorpus.load(path)
      replay = Sim::Battle::ScenarioCorpus.run(entry)
      identical = replay[:semantic].deep_stringify_keys == replay[:expected].deep_stringify_keys
      puts "#{identical ? 'OK' : 'CHANGED'} #{entry[:id]} seed=#{entry[:seed]}"
      failures << entry[:id] unless identical
    end
    abort "Semantic drift in: #{failures.join(', ')}" if failures.any?
  end

  def resolve_matchup!
    if ENV["MATCHUP_ID"].present?
      RoundMatchup.find(ENV["MATCHUP_ID"])
    elsif ENV["BATTLE_ID"].present?
      battle = Battle.find(ENV["BATTLE_ID"])
      Sim::Battle::Replay.find_matchup!(battle: battle)
    else
      abort "Set MATCHUP_ID or BATTLE_ID (see: bin/rails battle:list)"
    end
  end

  def default_replay_path(matchup_id)
    Rails.root.join("tmp/battle_dumps/replay_#{matchup_id}.json").to_s
  end

  def print_compare(compare)
    if compare[:identical]
      puts "Compare: identical to stored result_payload"
      return
    end

    movement = compare[:movement] || {}
    puts "Compare: winner_changed=#{compare[:winner_changed]}"
    puts "  semantic_identical=#{compare[:semantic_identical]}"
    if (first = compare.dig(:semantic, :first_divergence))
      puts "  first semantic divergence: #{first[:path]}"
    end
    puts "  stored: #{compare[:stored_summary]}"
    puts "  fresh:  #{compare[:fresh_summary]}"
    puts "  movement actions: stored=#{movement[:stored_count]} fresh=#{movement[:fresh_count]} changed=#{movement[:changed]}"
    Array(movement[:diffs]).each do |diff|
      puts "  [#{diff[:index]}] stored=#{diff[:stored].inspect}"
      puts "         fresh=#{diff[:fresh].inspect}"
    end
  end

  def deep_stringify(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, entry), memo| memo[key.to_s] = deep_stringify(entry) }
    when Array
      value.map { |entry| deep_stringify(entry) }
    else
      value
    end
  end
end
