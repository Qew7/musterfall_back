require "sim_test_helper"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../../../script/profilers/profile"

class SimProfileTest < SimTestCase
  test "invalid measurement counts fail before loading or running a scenario" do
    assert_raises(OptionParser::InvalidArgument) { SimProfile.new(%w[--runs 0]) }
    assert_raises(OptionParser::InvalidArgument) { SimProfile.new(%w[--warmup -1]) }
    assert_raises(OptionParser::InvalidArgument) { SimProfile.new(%w[--timeout 0]) }
  end

  test "CLI preserves inputs and detects drift in comparison results" do
    Dir.mktmpdir("sim-profile") do |dir|
      fixture = File.join(SimTools::ROOT, "test/fixtures/battle_scenarios/matchup_118.json")
      original = File.binread(fixture)
      output = File.join(dir, "baseline")
      args = [ "--runs", "1", "--warmup", "0", "--check", "--output", output ]
      stdout, stderr, status = run_profile(*args, fixture)
      assert status.success?, "#{stdout}\n#{stderr}"
      report_path = File.join(output, "report.json")
      report = JSON.parse(File.read(report_path))
      row = report.fetch("scenarios").first
      assert row.fetch("expected_equal")
      assert_operator row.fetch("median_allocated"), :>, 0
      row["semantic_sha256"] = "changed"
      File.write(report_path, JSON.generate(report))

      stdout, stderr, status = run_profile(*args, "--output", File.join(dir, "after"), "--compare", report_path, fixture)
      assert_equal 1, status.exitstatus, "#{stdout}\n#{stderr}"
      after = JSON.parse(File.read(File.join(dir, "after/report.json"))).fetch("scenarios").first
      assert_equal false, after.fetch("comparison").fetch("semantic_equal")
      assert_equal original, File.binread(fixture)
    end
  end

  test "run dispatcher prints usage and rejects unknown commands" do
    stdout, stderr, status = run_dispatch
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_match(/profile \[profile.rb flags/, stdout)

    stdout, stderr, status = run_dispatch("nope")
    assert_equal 1, status.exitstatus
    assert_match(/unknown command: nope/, stderr)
    assert_match(/Usage:/, stdout)
  end

  private

  def run_profile(*args)
    Open3.capture3(RbConfig.ruby, "-EUTF-8", File.join(SimTools::ROOT, "script/profilers/profile.rb"), *args)
  end

  def run_dispatch(*args)
    Open3.capture3(RbConfig.ruby, "-EUTF-8", File.join(SimTools::ROOT, "script/profilers/run.rb"), *args)
  end
end
