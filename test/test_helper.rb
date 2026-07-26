ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/sim_helpers"

if Faction.count.zero?
  load Rails.root.join("db/seeds.rb")
end

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
    include SimHelpers

    setup do
      load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    end
  end
end


