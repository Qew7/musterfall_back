require_relative "../script/support/sim_boot"
require "active_support/test_case"
require "minitest/autorun"
require_relative "support/battle_scenarios"

class SimTestCase < ActiveSupport::TestCase
  include BattleScenarios
end
