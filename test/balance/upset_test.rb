# frozen_string_literal: true

require "test_helper"

class BalanceUpsetTest < ActiveSupport::TestCase
  test "duel_counts counts cheaper template wins" do
    left = Struct.new(:cost).new(100)
    right = Struct.new(:cost).new(200)
    units = { "cheap" => left, "dear" => right }
    runs = [
      Struct.new(:left_template, :right_template, :iterations, :left_wins, :right_wins).new("cheap", "dear", 10, 7, 3)
    ]

    counts = Balance::Upset.duel_counts(runs, units)

    assert_equal 7, counts[:upset_count]
    assert_in_delta 0.7, counts[:upset_rate], 0.001
  end

  test "duel_counts ignores equal cost" do
    unit = Struct.new(:cost).new(100)
    units = { "a" => unit, "b" => unit }
    runs = [
      Struct.new(:left_template, :right_template, :iterations, :left_wins, :right_wins).new("a", "b", 10, 6, 4)
    ]

    counts = Balance::Upset.duel_counts(runs, units)

    assert_equal 0, counts[:upset_count]
    assert_equal 0.0, counts[:upset_rate]
  end
end
