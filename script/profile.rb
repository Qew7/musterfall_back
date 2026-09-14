require 'active_support/all'
require 'zeitwerk'
require 'json'
require 'timeout'
require 'stackprof'
$stdout.sync = true
loader = Zeitwerk::Loader.new
loader.push_dir('/Users/mkveisg1/Musterfall/backend/app/domain')
loader.setup
catalog = Sim::Catalog.new(formation_rules: { max_files: 5 }, model_classes: [], factions: [], units: [], heroes: [], abilities: [], hero_upgrades: [])
paths = Dir['/Users/mkveisg1/Musterfall/backend/test/fixtures/battle_scenarios/*.json'].sort
puts JSON.generate(ruby: RUBY_DESCRIPTION, native_obb: Sim::Geometry::Obb.native?)
paths.each do |path|
  entry = Sim::Battle::ScenarioCorpus.load(path)
  allocated = GC.stat(:total_allocated_objects)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = nil
  profile = StackProf.run(mode: :cpu, interval: 1000, raw: true) do
    Timeout.timeout(40) { result = Sim::Battle::ScenarioCorpus.run(entry, catalog: catalog) }
  end
  seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  File.binwrite("/tmp/musterfall-ai-review/#{entry[:id]}.dump", Marshal.dump(profile))
  puts JSON.generate(id: entry[:id], units: entry[:attacker][:roster].size + entry[:defender][:roster].size, seconds: seconds.round(3), allocated: GC.stat(:total_allocated_objects) - allocated, semantic_equal: result[:semantic].deep_stringify_keys == result[:expected].deep_stringify_keys, samples: profile[:samples], report_bytes: JSON.generate(result[:result]).bytesize)
  top = profile[:frames].values.sort_by { |frame| -frame[:samples] }.first(12)
  puts JSON.generate(top.map { |frame| frame.slice(:name, :file, :line, :samples, :total_samples) })
rescue Timeout::Error => e
  puts JSON.generate(id: entry[:id], error: e.class.name, limit_seconds: 40)
  break
rescue StandardError => e
  warn "#{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
  break
end
