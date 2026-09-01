# frozen_string_literal: true

namespace :db do
  desc "Load Solid Queue schema into the queue database (safe when queue shares primary DB)"
  task load_queue_schema: :environment do
    config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "queue")
    abort "No queue database configured for #{Rails.env}" unless config

    ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |connection|
      if connection.table_exists?(:solid_queue_jobs)
        puts "Solid Queue schema already loaded (#{Rails.env}/queue)"
        next
      end

      load Rails.root.join("db/queue_schema.rb")
    end
    puts "Loaded db/queue_schema.rb into #{config.database} (#{Rails.env}/queue)"
  end
end
