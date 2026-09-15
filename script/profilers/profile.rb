require "optparse"
require "fileutils"
require "digest"
require "timeout"

# Run directly with Ruby; no Rails boot, database, or writes to battle fixtures.
class SimProfile
  def initialize(argv)
    @options = { kernel: "auto", runs: 3, warmup: 1, timeout: 60, stackprof: nil, check: false }
    parser = OptionParser.new do |p|
      p.banner = "Usage: ruby script/profilers/profile.rb [options] [scenario.json ...]"
      p.on("--kernel MODE", %w[auto ruby native], "OBB implementation (default: auto)") { |v| @options[:kernel] = v }
      p.on("--runs N", Integer, "Measured runs per scenario (default: 3)") { |v| @options[:runs] = v }
      p.on("--warmup N", Integer, "Warmup runs per scenario (default: 1)") { |v| @options[:warmup] = v }
      p.on("--timeout SECONDS", Float, "Limit for each simulation (default: 60)") { |v| @options[:timeout] = v }
      p.on("--stackprof MODE", %w[cpu wall object], "Optional sampling; affects measured time") { |v| @options[:stackprof] = v }
      p.on("--output DIR", "Report directory (default: tmp/profiles/<timestamp>)") { |v| @options[:output] = v }
      p.on("--compare REPORT", "Compare results and medians with a previous report.json") { |v| @options[:compare] = v }
      p.on("--check", "Fail on semantic drift from fixtures or comparison report") { @options[:check] = true }
      p.on("-h", "--help") { puts p; exit }
    end
    @paths = parser.parse(argv)
    raise OptionParser::InvalidArgument, "runs/timeout must be positive; warmup must be nonnegative" unless
      @options[:runs].positive? && @options[:timeout].positive? && @options[:warmup] >= 0
  end

  def call
    ENV["SIM_OBB_MODE"] = @options[:kernel]
    require_relative "../support/sim_boot"
    require "stackprof" if @options[:stackprof]
    @catalog = SimTools.catalog
    @paths = Dir[File.join(SimTools::ROOT, "test/fixtures/battle_scenarios/*.json")].sort if @paths.empty?
    raise ArgumentError, "no scenarios found" if @paths.empty?

    @output = File.expand_path(@options[:output] || File.join(SimTools::ROOT, "tmp/profiles", Time.now.strftime("%Y%m%d-%H%M%S-#{Process.pid}")))
    @baseline = @options[:compare] ? JSON.parse(File.read(@options[:compare])).fetch("scenarios") : []
    FileUtils.mkdir_p(@output)
    $stdout.sync = true
    metadata = {
      ruby: RUBY_DESCRIPTION, native_obb: Sim::Geometry::Obb.native?,
      stackprof: @options[:stackprof], runs: @options[:runs], warmup: @options[:warmup],
      timing: "Simulator.call only; input copying, GC.start and report serialization excluded"
    }
    puts JSON.generate(metadata)
    records = @paths.map.with_index { |path, index| profile(path, index) }
    File.write(File.join(@output, "report.json"), JSON.pretty_generate(metadata.merge(scenarios: records)))
    puts "Report: #{File.join(@output, 'report.json')}"
    return 1 if records.any? { |row| row[:error] || row[:deterministic] == false }
    return 1 if @options[:check] && records.any? { |row| row[:expected_equal] == false || row.dig(:comparison, :semantic_equal) == false || row.dig(:comparison, :input_equal) == false }

    0
  end

  private

  def profile(path, index)
    entry = Sim::Battle::ScenarioCorpus.load(path)
    input_hash = digest(entry.slice(:attacker, :defender, :seed, :map_seed))
    @options[:warmup].times { simulate(entry) }
    samples = []
    semantics = []
    expected_equal = true
    @options[:runs].times do |run|
      sample, result, dump = measure(entry)
      semantic = Sim::Battle::SemanticSnapshot.build(result)
      samples << sample
      semantics << digest(semantic)
      expected_equal &&= semantic.deep_stringify_keys == entry[:expected]&.deep_stringify_keys
      File.write(File.join(@output, "#{index}-semantic.json"), JSON.pretty_generate(semantic)) if run.zero?
      File.binwrite(File.join(@output, "#{index}-#{run}.dump"), Marshal.dump(dump)) if dump
    end
    row = {
      id: entry[:id], input_sha256: input_hash, semantic_sha256: semantics.first,
      units: entry[:attacker][:roster].length + entry[:defender][:roster].length,
      median_seconds: median(samples.map { |s| s[:seconds] }),
      median_allocated: median(samples.map { |s| s[:allocated] }),
      samples: samples, deterministic: semantics.uniq.length == 1, expected_equal: expected_equal
    }
    if @options[:compare]
      before = @baseline.find { |prior| prior["id"] == row[:id] }
      raise ArgumentError, "comparison report has no scenario #{row[:id]}" unless before

      row[:comparison] = {
        input_equal: before["input_sha256"] == input_hash,
        semantic_equal: before["semantic_sha256"] == semantics.first,
        speedup: before.fetch("median_seconds") / row[:median_seconds],
        allocated_ratio: row[:median_allocated].to_f / before.fetch("median_allocated")
      }
    end
    puts JSON.generate(row.except(:samples))
    row
  rescue StandardError => error
    row = { path: path, error: "#{error.class}: #{error.message}" }
    warn JSON.generate(row)
    row
  end

  def simulate(entry)
    value = entry.deep_dup
    Timeout.timeout(@options[:timeout]) do
      Sim::Battle::Simulator.call(
        value.fetch(:attacker), value.fetch(:defender), @catalog,
        rng: Sim::Rng::Seeded.new(value.fetch(:seed)), map_seed: value.fetch(:map_seed)
      )
    end
  end

  def measure(entry)
    value = entry.deep_dup
    rng = Sim::Rng::Seeded.new(value.fetch(:seed))
    result = nil
    dump = nil
    GC.start
    allocated = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    run = lambda do
      result = Timeout.timeout(@options[:timeout]) do
        Sim::Battle::Simulator.call(value.fetch(:attacker), value.fetch(:defender), @catalog, rng: rng, map_seed: value.fetch(:map_seed))
      end
    end
    @options[:stackprof] ? dump = StackProf.run(mode: @options[:stackprof].to_sym, raw: true, &run) : run.call
    sample = { seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, allocated: GC.stat(:total_allocated_objects) - allocated }
    [ sample, result, dump ]
  end

  def digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  end

  def canonical(value)
    case value
    when Hash then value.stringify_keys.sort.to_h.transform_values { |entry| canonical(entry) }
    when Array then value.map { |entry| canonical(entry) }
    else value
    end
  end

  def median(values)
    sorted = values.sort
    (sorted[(sorted.length - 1) / 2] + sorted[sorted.length / 2]) / 2.0
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit SimProfile.new(ARGV).call
  rescue LoadError, ArgumentError, OptionParser::ParseError, SystemCallError => error
    warn "#{error.class}: #{error.message}"
    exit 1
  end
end
