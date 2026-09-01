require "test_helper"

class BalanceSimulationParallelismTest < ActiveSupport::TestCase
  setup do
    @cache_path = Balance::Simulation::Parallelism::CACHE_PATH
    @previous_cache = @cache_path.read if @cache_path.exist?
    @cache_path.delete if @cache_path.exist?
  end

  teardown do
    @cache_path.delete if @cache_path.exist?
    @cache_path.write(@previous_cache) if @previous_cache
  end

  test "returns env override without calibration" do
    previous = ENV["BALANCE_SIMULATION_WORKERS"]
    ENV["BALANCE_SIMULATION_WORKERS"] = "3"
    assert_equal 3, Balance::Simulation::Parallelism.worker_count
  ensure
    if previous.nil?
      ENV.delete("BALANCE_SIMULATION_WORKERS")
    else
      ENV["BALANCE_SIMULATION_WORKERS"] = previous
    end
  end

  test "reads cached worker count when fingerprint matches" do
    Balance::Simulation::Parallelism.write_cache(2)
    assert_equal 2, Balance::Simulation::Parallelism.read_cache
  end

  test "calibrate picks parallel workers when speedup is high" do
    Balance::Simulation::Parallelism.singleton_class.define_method(:benchmark_serial) { |*_args| 10.0 }
    Balance::Simulation::Parallelism.singleton_class.define_method(:benchmark_parallel) { |*_args, **_kwargs| 5.0 }

    assert_equal Balance::Simulation::Parallelism.max_workers, Balance::Simulation::Parallelism.calibrate
  ensure
    Balance::Simulation::Parallelism.singleton_class.send(:remove_method, :benchmark_serial)
    Balance::Simulation::Parallelism.singleton_class.send(:remove_method, :benchmark_parallel)
  end

  test "calibrate falls back to one worker when speedup is low" do
    Balance::Simulation::Parallelism.singleton_class.define_method(:benchmark_serial) { |*_args| 10.0 }
    Balance::Simulation::Parallelism.singleton_class.define_method(:benchmark_parallel) { |*_args, **_kwargs| 9.5 }

    assert_equal 1, Balance::Simulation::Parallelism.calibrate
  ensure
    Balance::Simulation::Parallelism.singleton_class.send(:remove_method, :benchmark_serial)
    Balance::Simulation::Parallelism.singleton_class.send(:remove_method, :benchmark_parallel)
  end
end
