require "test_helper"

class SimBattleScenarioCorpusTest < ActiveSupport::TestCase
  test "checked-in real battle corpus has no semantic drift" do
    paths = Dir[Rails.root.join("test/fixtures/battle_scenarios/*.{json,yml,yaml}")].sort
    assert_operator paths.length, :>=, 5

    paths.each do |path|
      entry = Sim::Battle::ScenarioCorpus.load(path)
      replay = Sim::Battle::ScenarioCorpus.run(entry, catalog: catalog)

      assert_equal entry[:expected].deep_stringify_keys,
                   replay[:semantic].deep_stringify_keys,
                   "#{entry[:id]} seed=#{entry[:seed]} changed"
    end
  end
end
