ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/sim_helpers"
require_relative "support/battle_scenarios"
require_relative "support/battle_scenario_runner"
require_relative "support/battle_invariants"
require_relative "support/pathing_audit"

if Faction.count.zero?
  load Rails.root.join("db/seeds.rb")
end

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
    include SimHelpers
    include BattleScenarios

    setup do
      load Rails.root.join("db/seeds.rb") if Faction.count.zero?
    end
  end
end
