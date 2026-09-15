# Replay one RoundMatchup with call counts + coarse timers. No sim source changes.
# docker exec musterfall-backend-1 bin/rails runner script/profilers/diagnose_matchup.rb 660
matchup_id = Integer(ARGV[0] || ENV.fetch("MATCHUP_ID", "660"))
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
stats = Hash.new { |h, k| h[k] = { n: 0, t: 0.0 } }

wrap_singleton = lambda do |mod, name, time: false|
  original = mod.method(name)
  key = "#{mod.name}.#{name}"
  mod.define_singleton_method(name) do |*args, **kwargs, &blk|
    row = stats[key]
    row[:n] += 1
    if time
      started = clock.call
      original.call(*args, **kwargs, &blk)
    else
      original.call(*args, **kwargs, &blk)
    end
  ensure
    row[:t] += clock.call - started if time && started
  end
end

wrap_instance = lambda do |klass, name, time: false|
  key = "#{klass.name}##{name}"
  klass.prepend(Module.new do
    define_method(name) do |*args, **kwargs, &blk|
      row = stats[key]
      row[:n] += 1
      if time
        started = clock.call
        super(*args, **kwargs, &blk)
      else
        super(*args, **kwargs, &blk)
      end
    ensure
      row[:t] += clock.call - started if time && started
    end
  end)
end

merge_n = 0
Hash.class_eval do
  alias_method :__diagnose_merge, :merge
  def merge(*args, **kwargs, &blk)
    Thread.current[:diagnose_merge] = Thread.current[:diagnose_merge].to_i + 1
    __diagnose_merge(*args, **kwargs, &blk)
  end
end

obb = Sim::Geometry::Obb
wrap_singleton.call(obb, :overlap?, time: false)
wrap_singleton.call(obb, :distance, time: false)
wrap_singleton.call(obb, :kernel, time: false)
wrap_singleton.call(obb, :trig, time: false)
if obb.native?
  wrap_singleton.call(obb::Native, :overlap?, time: false)
  wrap_singleton.call(obb::Native, :distance, time: false)
end
wrap_singleton.call(Sim::Geometry::Battlefield, :tray_on_battlefield?, time: false)
wrap_singleton.call(Sim::Battle::Pathing, :plan_approach, time: true)
wrap_singleton.call(Sim::Battle::Pathing::ManeuverSequence, :along, time: true)
wrap_singleton.call(Sim::Battle::Pathing::Maneuvers, :plan_segment, time: true)
wrap_instance.call(Sim::Battle::Pathing::Obstacles, :first_blocker, time: true)
wrap_singleton.call(Sim::Battle::Round, :play, time: true)
wrap_singleton.call(Sim::Battle::Turn, :play, time: true)
wrap_singleton.call(Sim::Battle::Phases::Movement, :play, time: true)
wrap_singleton.call(Sim::Battle::Decisions::Reposition, :seekers, time: true) if Sim::Battle::Decisions::Reposition.respond_to?(:seekers)

matchup = RoundMatchup.find(matchup_id)
atk = matchup.attacker_player
defn = matchup.defender_player
roster = lambda do |player|
  Array(player[:roster] || player[:combatants]).map do |row|
    {
      name: row[:name],
      template: row[:template_key] || row[:id],
      flying: Array(row[:abilities]).include?("flying") || row[:flying],
      mv: row[:movement],
      models: row[:models] || row[:starting_models]
    }
  end
end

payload = matchup.result_payload || {}
stored_rounds = Array(payload["rounds"])
action_types = Hash.new(0)
movement_kinds = Hash.new(0)
stored_rounds.each do |round|
  Array(round["turns"]).each do |turn|
    Array(turn["phases"]).each do |phase|
      Array(phase["actions"]).each do |action|
        type = action["type"].to_s
        action_types[type] += 1
        next unless type == "movement"

        kind = action.dig("maneuver", "kind").to_s
        movement_kinds[kind] += 1
      end
    end
  end
end

header = {
  matchup_id: matchup.id,
  game_id: matchup.game_id,
  round: matchup.campaign_round,
  seed: matchup.seed,
  native_obb: obb.native?,
  ruby: RUBY_DESCRIPTION,
  units: "#{roster.call(atk).size}+#{roster.call(defn).size}",
  attacker: roster.call(atk),
  defender: roster.call(defn),
  stored: {
    sim_rounds: stored_rounds.size,
    payload_kb: JSON.generate(payload).bytesize / 1024,
    action_types: action_types,
    movement_kinds: movement_kinds,
    db_created_to_updated_s: (matchup.updated_at - matchup.created_at).to_f.round(2)
  }
}
warn JSON.pretty_generate(header)

catalog = Sim::Catalog::Loader.load
map_seed = Sim::Battle::TerrainMap.map_seed(rng_seed: matchup.game.rng_seed, round: matchup.campaign_round)
GC.start
alloc0 = GC.stat(:total_allocated_objects)
Thread.current[:diagnose_merge] = 0
started = clock.call
result = Sim::Battle::Simulator.call(
  atk,
  defn,
  catalog,
  rng: Sim::Rng::Seeded.new(matchup.seed),
  map_seed: map_seed
)
elapsed = clock.call - started
merge_n = Thread.current[:diagnose_merge].to_i
alloc = GC.stat(:total_allocated_objects) - alloc0

report = header.merge(
  replay_seconds: elapsed.round(3),
  allocated: alloc,
  hash_merge: merge_n,
  winner: result[:summary],
  calls: stats.sort_by { |_k, row| -row[:t] }.to_h.transform_values { |row|
    { n: row[:n], seconds: row[:t].round(3) }
  }
)
out = "tmp/diagnose_matchup_#{matchup_id}.json"
File.write(out, JSON.pretty_generate(report))
puts JSON.pretty_generate(report)
warn "wrote #{out}"
