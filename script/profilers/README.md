# Simulation profiling

Entry point from `backend`:

```sh
ruby script/profilers/run.rb
ruby script/profilers/run.rb compile
ruby script/profilers/run.rb profile --kernel native --check --output tmp/profiles/before
ruby script/profilers/run.rb profile --kernel native --check --compare tmp/profiles/before/report.json --output tmp/profiles/after
ruby script/profilers/run.rb cpu test/fixtures/battle_scenarios/matchup_122.json
ruby script/profilers/run.rb diagnose 689
ruby script/profilers/run.rb overlaps 15
ruby script/profilers/run.rb overlaps --self-check
```

`diagnose` and `overlaps` use the Compose backend container when it is up, otherwise local `bin/rails`. `PROFILER_LOCAL=1` forces local. `profile` / `cpu` / `compile` always run on the host.

| Command | Script | Purpose |
| --- | --- | --- |
| `profile` | `profile.rb` | Repeatable corpus timing, allocations, `--compare` / `--check` |
| `cpu` | `profile.rb --stackprof` | Method-level CPU, then `stackprof --text` |
| `diagnose` | `diagnose_matchup.rb` | Call counts and timers for a stored matchup |
| `overlaps` | `scan_overlaps.rb` | True OBB overlaps in the last N completed matchups |
| `compile` | `rake sim:compile_obb` | Rebuild the OBB C kernel |

`legacy/profile_hot.rb` is archived: it targets the former route implementation.

The profiler and geometry tests load the domain directly: Rails and PostgreSQL are not required for `profile`. Shared bootstrapping stays in `script/support/sim_boot.rb` because geometry tests also use it. Reports land in `tmp/`. This directory is excluded from RuboCop.

The default corpus is `test/fixtures/battle_scenarios/*.json`. Pass individual paths to `profile` to select scenarios. Each scenario gets one warmup and three measured runs; `--runs`, `--warmup` and `--timeout` override these defaults. Each run copies its inputs because the simulator mutates armies. Timing excludes copying, explicit GC and semantic report construction. Avoid concurrent simulations when measuring.

`report.json` contains samples, medians, allocated object counts, input and semantic hashes, runtime and active kernel. `--check` rejects fixture drift, changed comparison inputs and changed results; execution errors and nondeterminism always fail. Fixtures are never rewritten. A speedup above 1 means faster; an allocation ratio below 1 means fewer objects. Compare unsampled runs for timing. Record the commit and working diff alongside results when sharing measurements.

`--kernel ruby` forces the fallback; `--kernel native` fails if the extension is missing or outdated. `auto` uses native when available. Application/test processes use the equivalent `SIM_OBB_MODE` environment variable, read at boot. Recompile after changing C source and restart processes that already loaded the extension. Build with the same Ruby and OS as the target process.

Fast tests, including independent Ruby/native parity checks:

```sh
bundle exec ruby -Itest -e 'ARGV.each { |path| require_relative path }' test/game/battle/pathing_route_test.rb test/game/battle/pathing_obstacles_test.rb test/game/battle/route_search_test.rb test/game/battle/obb_geometry_test.rb test/game/battle/obb_native_parity_test.rb
```

Parity checks skip if native is unavailable; use `SIM_OBB_MODE=native` to require it. CI compiles the extension, runs standalone fallback tests, then the Rails suite with native required. `script/experiment.rb` was removed: its board-check experiment is already implemented in production; use `--compare` for new changes.
