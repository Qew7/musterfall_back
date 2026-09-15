require "sim_test_helper"

class SimRouteSearchTest < SimTestCase
  Route = Sim::Battle::Pathing::Route

  # A small graph with equal-length branches and configurable disconnected goal.
  # Collision answers are independent of the search, exposing tie and reachability
  # contracts without relying on terrain generation or an exact battle outcome.
  class BranchWorld
    attr_reader :batch_queries

    def initialize(reachable: true)
      @reachable = reachable
      @batch_queries = 0
    end

    def route_points(*)
      [ { x: 15.0, y: 8.0 }, { x: 15.0, y: 16.0 } ]
    end

    def first_segment_clear?(_mover, to, **)
      to[:x] == 15.0
    end

    def wheel_clear?(*)
      true
    end

    def segments_open_mask(_mover, _from, dests, _contact)
      @batch_queries += dests.length
      dests.map { |dest| @reachable && dest[:x] == 25.0 ? "\x01" : "\x00" }.join
    end
  end

  test "equal cost routes keep node order and avoid dominated collision queries" do
    world = BranchWorld.new
    start = { x: 5.0, y: 12.0 }
    finish = { x: 25.0, y: 12.0 }
    mover = BattleScenarios.combatant(**start, base_width: 0, base_depth: 0, movement: 0)
    path = Route::Search.new(mover, start, finish, world, nil).call

    assert_equal [ start, { x: 15.0, y: 8.0 }, finish ], path
    assert_equal 1, world.batch_queries, "the second equal-cost branch cannot improve the goal"
  end

  test "unreachable goal returns the nearest reachable node in stable order" do
    world = BranchWorld.new(reachable: false)
    start = { x: 5.0, y: 12.0 }
    finish = { x: 25.0, y: 12.0 }
    mover = BattleScenarios.combatant(**start, base_width: 0, base_depth: 0, movement: 0)
    path = Route::Search.new(mover, start, finish, world, nil).call

    assert_equal [ start, { x: 15.0, y: 8.0 } ], path
    assert_equal 2, world.batch_queries
  end
end
