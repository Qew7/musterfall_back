# One-off pathing profile. docker exec musterfall-backend-1 bin/rails runner script/profilers/legacy/profile_hot.rb 666
matchup_id = Integer(ARGV[0] || ENV.fetch("MATCHUP_ID", "666"))
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
stats = Hash.new { |h, k| h[k] = { n: 0, t: 0.0 } }
extra = {
  visible_direct: 0,
  visible_graph: 0,
  graph_nodes: [],
  hop_edges: 0,
  hop_pairs: 0,
  los_fh_hit: 0,
  los_fh_miss: 0,
  los_sg_hit: 0,
  los_sg_miss: 0
}

wrap_singleton = lambda do |mod, name, time: true|
  original = mod.method(name)
  key = "#{mod.name}.#{name}"
  mod.define_singleton_method(name) do |*args, **kwargs, &blk|
    row = stats[key]
    row[:n] += 1
    started = clock.call if time
    original.call(*args, **kwargs, &blk)
  ensure
    row[:t] += clock.call - started if time && started
  end
end

wrap_instance = lambda do |klass, name, time: true|
  key = "#{klass.name}##{name}"
  klass.prepend(Module.new do
    define_method(name) do |*args, **kwargs, &blk|
      row = stats[key]
      row[:n] += 1
      started = clock.call if time
      super(*args, **kwargs, &blk)
    ensure
      row[:t] += clock.call - started if time && started
    end
  end)
end

Hash.class_eval do
  alias_method :__profile_merge, :merge
  def merge(*args, **kwargs, &blk)
    Thread.current[:profile_merge] = Thread.current[:profile_merge].to_i + 1
    __profile_merge(*args, **kwargs, &blk)
  end
end

obb = Sim::Geometry::Obb
wrap_singleton.call(obb, :trig)
wrap_singleton.call(obb, :half_sizes)
if obb.native?
  wrap_singleton.call(obb::Native, :blocker_index)
  wrap_singleton.call(obb::Native, :distance)
  wrap_singleton.call(obb::Native, :overlap?)
end
wrap_singleton.call(Sim::Geometry::Battlefield, :tray_on_battlefield?)
wrap_singleton.call(Sim::Geometry::Battlefield, :fit_tray_on_battlefield)
wrap_singleton.call(Sim::Geometry::Battlefield, :wheel_pose)
wrap_singleton.call(Sim::Battle::Pathing, :plan_approach)
wrap_singleton.call(Sim::Battle::Pathing::Route, :pull)
wrap_singleton.call(Sim::Battle::Pathing::Route, :taut)
wrap_instance.call(Sim::Battle::Pathing::Obstacles, :first_blocker)
wrap_instance.call(Sim::Battle::Pathing::Obstacles, :route_points)
wrap_instance.call(Sim::Battle::Pathing::Obstacles, :first_segment_clear?)
wrap_instance.call(Sim::Battle::Pathing::Obstacles, :wheel_clear?)
wrap_instance.call(Sim::Battle::Pathing::Obstacles, :segment_clear?)
wrap_instance.call(Sim::Battle::Pathing::Obstacles, :first_hit)
wrap_instance.call(Sim::Battle::Pathing::Obstacles, :translation_clear?)
wrap_instance.call(Sim::Battle::Pathing::Obstacles, :except)
wrap_singleton.call(Sim::Battle::Phases::Movement, :play)

visible_orig = Sim::Battle::Pathing::Route.method(:visible_path)
Sim::Battle::Pathing::Route.define_singleton_method(:visible_path) do |mover, start, finish, world, contact_id, los = {}|
  started = clock.call
  stats["Sim::Battle::Pathing::Route.visible_path"][:n] += 1
  result = visible_orig.call(mover, start, finish, world, contact_id, los)
  stats["Sim::Battle::Pathing::Route.visible_path"][:t] += clock.call - started
  if result && result.length == 2 &&
      Sim::Battle::Pathing::Route.same?(result[0], start) &&
      Sim::Battle::Pathing::Route.same?(result[1], finish)
    extra[:visible_direct] += 1
  else
    extra[:visible_graph] += 1
    extra[:graph_nodes] << result.length if result
  end
  result
end

hop_orig = Sim::Battle::Pathing::Route.method(:hop_edges)
Sim::Battle::Pathing::Route.define_singleton_method(:hop_edges) do |u, nodes, finish, finish_index, mover, world, contact_id, los|
  extra[:hop_edges] += 1
  extra[:hop_pairs] += nodes.length - 1
  hop_orig.call(u, nodes, finish, finish_index, mover, world, contact_id, los)
end

fh_orig = Sim::Battle::Pathing::Route.method(:first_hop_open?)
Sim::Battle::Pathing::Route.define_singleton_method(:first_hop_open?) do |world, mover, vertex, finish, contact_id, los|
  key = [ :fh, vertex[:x], vertex[:y], finish[:x], finish[:y] ]
  if los.key?(key)
    extra[:los_fh_hit] += 1
  else
    extra[:los_fh_miss] += 1
  end
  fh_orig.call(world, mover, vertex, finish, contact_id, los)
end

sg_orig = Sim::Battle::Pathing::Route.method(:segment_open?)
Sim::Battle::Pathing::Route.define_singleton_method(:segment_open?) do |world, mover, from, to, contact_id, los|
  key = [ :sg, from[:x], from[:y], to[:x], to[:y] ]
  if los.key?(key)
    extra[:los_sg_hit] += 1
  else
    extra[:los_sg_miss] += 1
  end
  sg_orig.call(world, mover, from, to, contact_id, los)
end

matchup = RoundMatchup.find(matchup_id)
catalog = Sim::Catalog::Loader.load
map_seed = Sim::Battle::TerrainMap.map_seed(rng_seed: matchup.game.rng_seed, round: matchup.campaign_round)
atk = matchup.attacker_player
defn = matchup.defender_player
units = "#{Array(atk[:roster] || atk[:combatants]).size}+#{Array(defn[:roster] || defn[:combatants]).size}"

GC.start
alloc0 = GC.stat(:total_allocated_objects)
Thread.current[:profile_merge] = 0
started = clock.call
result = Sim::Battle::Simulator.call(
  atk,
  defn,
  catalog,
  rng: Sim::Rng::Seeded.new(matchup.seed),
  map_seed: map_seed
)
elapsed = clock.call - started
nodes = extra[:graph_nodes]
report = {
  matchup_id: matchup_id,
  units: units,
  native: obb.native?,
  replay_seconds: elapsed.round(3),
  allocated: GC.stat(:total_allocated_objects) - alloc0,
  hash_merge: Thread.current[:profile_merge].to_i,
  winner: result[:summary],
  visible: {
    direct: extra[:visible_direct],
    graph: extra[:visible_graph],
    hop_edges: extra[:hop_edges],
    hop_pairs: extra[:hop_pairs],
    graph_nodes_p50: nodes.empty? ? 0 : nodes.sort[nodes.length / 2],
    graph_nodes_max: nodes.max || 0,
    graph_nodes_sum: nodes.sum
  },
  los_memo: {
    first_hop: { hit: extra[:los_fh_hit], miss: extra[:los_fh_miss] },
    segment: { hit: extra[:los_sg_hit], miss: extra[:los_sg_miss] }
  },
  calls: stats.sort_by { |_k, row| -row[:t] }.to_h.transform_values { |row|
    { n: row[:n], seconds: row[:t].round(3), us_each: row[:n].positive? ? ((row[:t] / row[:n]) * 1_000_000).round(1) : 0 }
  }
}
File.write("tmp/profile_hot_#{matchup_id}.json", JSON.pretty_generate(report))
puts JSON.pretty_generate(report)
