require "benchmark"
require "etc"
require "yaml"

module Balance
  module Simulation
    module Parallelism
      CACHE_PATH = Rails.root.join("tmp/balance_simulation_workers.yml")
      SPEEDUP_THRESHOLD = 1.15
      CALIBRATION_BATTLES = 2

      module_function

      def worker_count
        if ENV["BALANCE_SIMULATION_WORKERS"].present?
          return ENV["BALANCE_SIMULATION_WORKERS"].to_i.clamp(1, max_workers)
        end

        return 1 if Rails.env.test?

        return calibrate_and_cache if ENV["BALANCE_SIMULATION_RECALIBRATE"].present?

        cached = read_cache
        return cached if cached

        calibrate_and_cache
      end

      def calibrate_and_cache
        count = calibrate
        write_cache(count)
        count
      end

      def max_workers
        pool = ENV.fetch("SOLID_QUEUE_THREADS", 4).to_i
        processes = ENV.fetch("JOB_CONCURRENCY", 1).to_i
        (pool * processes).clamp(1, 32)
      end

      def calibrate
        workers = max_workers
        return 1 if workers <= 1
        return 1 if Etc.nprocessors <= 1

        catalog = Sim::Catalog::Loader.load
        version = CatalogVersion.current!
        run = BalanceSimulationRun.create!(
          catalog_version: version,
          status: "running",
          config: { round: 1, target_points: 300, hero_level: 1, budget_mode: "fixed" },
          seed: 88_001,
          started_at: Time.current
        )

        serial = benchmark_serial(catalog, run)
        parallel = benchmark_parallel(catalog, run, workers: [ 2, workers ].min)
        speedup = serial / parallel

        Rails.logger.info(
          "[Balance::Simulation::Parallelism] serial=#{serial.round(2)}s parallel=#{parallel.round(2)}s " \
          "speedup=#{speedup.round(2)} workers=#{speedup >= SPEEDUP_THRESHOLD ? workers : 1}"
        )

        speedup >= SPEEDUP_THRESHOLD ? workers : 1
      ensure
        run&.destroy
      end

      def benchmark_serial(catalog, run)
        ::Benchmark.realtime do
          CALIBRATION_BATTLES.times do |index|
            play_sample!(catalog, run, 10_000 + index)
          end
        end
      end

      def benchmark_parallel(catalog, run, workers:)
        ::Benchmark.realtime do
          threads = workers.times.map do |index|
            Thread.new do
              Rails.application.executor.wrap do
                play_sample!(catalog, run, 20_000 + index)
              end
            end
          end
          threads.each(&:join)
        end
      end

      def play_sample!(catalog, run, offset)
        Balance::Synthetic::Play.call!(
          run: run,
          catalog: catalog,
          rng: Sim::Rng::Seeded.new(run.seed + offset)
        )
      end

      def fingerprint
        "threads:#{ENV.fetch('SOLID_QUEUE_THREADS', 4)}:" \
          "processes:#{ENV.fetch('JOB_CONCURRENCY', 1)}:" \
          "nproc:#{Etc.nprocessors}"
      end

      def read_cache
        return nil unless CACHE_PATH.exist?

        data = YAML.safe_load(CACHE_PATH.read, permitted_classes: [ Time ], aliases: true) || {}
        return nil unless data["fingerprint"] == fingerprint

        data["workers"].to_i.clamp(1, max_workers)
      rescue StandardError
        nil
      end

      def write_cache(workers)
        CACHE_PATH.parent.mkpath
        CACHE_PATH.write({
          "workers" => workers,
          "fingerprint" => fingerprint,
          "calibrated_at" => Time.current.iso8601
        }.to_yaml)
      end
    end
  end
end
