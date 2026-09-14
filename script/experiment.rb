require 'active_support/all'
require 'zeitwerk'
require 'json'
require 'timeout'
$stdout.sync = true
loader = Zeitwerk::Loader.new
loader.push_dir('/Users/mkveisg1/Musterfall/backend/app/domain')
loader.setup
catalog = Sim::Catalog.new(formation_rules: { max_files: 5 }, model_classes: [], factions: [], units: [], heroes: [], abilities: [], hero_upgrades: [])
paths = Dir['/Users/mkveisg1/Musterfall/backend/test/fixtures/battle_scenarios/*.json'].sort
baselines = {}
records = []
def measure(path, catalog, label)
  entry = Sim::Battle::ScenarioCorpus.load(path)
  GC.start
  alloc = GC.stat(:total_allocated_objects)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = Timeout.timeout(40) { Sim::Battle::ScenarioCorpus.run(entry, catalog: catalog) }
  record = { variant: label, id: entry[:id], seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC)-started).round(3), allocated: GC.stat(:total_allocated_objects)-alloc, expected_equal: result[:semantic].deep_stringify_keys == result[:expected].deep_stringify_keys }
  [ record, result[:semantic] ]
end
paths = paths.values_at(0, 4)
paths.each do |path|
  record, semantic = measure(path, catalog, 'baseline')
  baselines[path] = semantic
  records << record
  puts JSON.generate(record)
end

# Exact AABB envelope of an oriented rectangle, with the existing tolerance.
# Temporary runtime prototype only; no repository source changes.
board = Sim::Geometry::Battlefield
original = board.method(:tray_on_battlefield?)
envelope = lambda do |unit|
  hw, hd = Sim::Geometry::Obb.half_sizes(unit)
  c, s = Sim::Geometry::Obb.trig(unit[:facing])
  rx = c.abs * hd + s.abs * hw
  ry = s.abs * hd + c.abs * hw
  x, y = unit[:x].to_f, unit[:y].to_f
  x-rx >= -1e-6 && x+rx <= 40.0+1e-6 && y-ry >= -1e-6 && y+ry <= 24.0+1e-6
end
rng = Random.new(17)
mismatches = 10000.times.count do
  pose = { x: rng.rand * 50 - 5, y: rng.rand * 34 - 5, facing: rng.rand * 720 - 180, base_width: rng.rand * 10, base_depth: rng.rand * 10 }
  original.call(pose) != envelope.call(pose)
end
puts JSON.generate(envelope_property_samples: 10000, mismatches: mismatches)
raise 'geometry mismatch' unless mismatches.zero?
board.define_singleton_method(:tray_on_battlefield?, &envelope)

paths.each do |path|
  record, semantic = measure(path, catalog, 'analytic_board_bounds')
  record[:baseline_semantic_equal] = semantic == baselines[path]
  records << record
  puts JSON.generate(record)
end
File.write('/tmp/musterfall-ai-review/experiment.json', JSON.pretty_generate(records))
