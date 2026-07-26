require "test_helper"

class SimRngSeededTest < ActiveSupport::TestCase
  test "same seed produces same sequence" do
    left = Sim::Rng::Seeded.new(42)
    right = Sim::Rng::Seeded.new(42)

    20.times do
      assert_in_delta left.rand, right.rand, 0.0000001
    end
  end

  test "different seeds diverge" do
    left = Sim::Rng::Seeded.new(1)
    right = Sim::Rng::Seeded.new(2)

    assert_not_equal 10.times.map { left.rand }, 10.times.map { right.rand }
  end

  test "pick returns nil for empty collection" do
    assert_nil Sim::Rng::Seeded.new(1).pick([])
  end

  test "pick returns an entry from the collection" do
    entries = %w[a b c]
    assert_includes entries, Sim::Rng::Seeded.new(9).pick(entries)
  end

  test "shuffle preserves membership" do
    entries = [ 1, 2, 3, 4, 5 ]
    assert_equal entries.sort, Sim::Rng::Seeded.new(3).shuffle(entries).sort
  end
end
