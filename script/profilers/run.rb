#!/usr/bin/env ruby
# frozen_string_literal: true

# Front door for simulation profilers. From backend:
#   ruby script/profilers/run.rb
#   ruby script/profilers/run.rb profile --kernel native --check
#   ruby script/profilers/run.rb diagnose 689
#   ruby script/profilers/run.rb overlaps 15

ROOT = File.expand_path("../..", __dir__)
REPO = File.expand_path("..", ROOT)

def usage
  puts <<~TEXT
    Usage: ruby script/profilers/run.rb COMMAND [args]

      compile                         build the OBB C kernel
      profile [profile.rb flags...]   corpus timing, no Rails
      cpu [scenario.json]             StackProf cpu dump + text
      diagnose MATCHUP_ID             call counts (Docker rails, else local)
      overlaps [N|--self-check|--json]

    PROFILER_LOCAL=1 skips Docker. Profile always runs on the host.
    Compare unsampled profile runs; cpu sampling distorts timing.
  TEXT
end

def container
  return if ENV["PROFILER_LOCAL"] == "1"

  id = `docker compose -f #{REPO}/docker-compose.yml ps -q backend 2>/dev/null`.strip
  return if id.empty?

  `docker inspect -f '{{.Name}}' #{id}`.strip.delete_prefix("/")
end

def rails_runner(*args)
  name = container
  if name
    warn "docker exec #{name}"
    exec("docker", "exec", name, "bin/rails", "runner", *args)
  else
    warn "local bin/rails (no backend container)"
    Dir.chdir(ROOT) { exec("bin/rails", "runner", *args) }
  end
end

cmd, *rest = ARGV
case cmd
when nil, "-h", "--help", "help"
  usage
when "compile"
  Dir.chdir(ROOT) { exec("bundle", "exec", "rake", "sim:compile_obb") }
when "profile"
  Dir.chdir(ROOT) { exec("bundle", "exec", "ruby", "script/profilers/profile.rb", *rest) }
when "cpu"
  Dir.chdir(ROOT) do
    out = "tmp/profiles/cpu"
    scenario = rest[0] || "test/fixtures/battle_scenarios/matchup_122.json"
    abort "profile failed" unless system(
      "bundle", "exec", "ruby", "script/profilers/profile.rb",
      "--stackprof", "cpu", "--runs", "1", "--output", out, scenario
    )
    dump = Dir[File.join(out, "*.dump")].max_by { |path| File.mtime(path) }
    abort "no stackprof dump in #{out}" unless dump
    exec("bundle", "exec", "stackprof", dump, "--text")
  end
when "diagnose"
  id = rest[0] or abort "diagnose MATCHUP_ID"
  rails_runner("script/profilers/diagnose_matchup.rb", id)
when "overlaps"
  rails_runner("script/profilers/scan_overlaps.rb", *rest)
else
  warn "unknown command: #{cmd}"
  usage
  exit 1
end
