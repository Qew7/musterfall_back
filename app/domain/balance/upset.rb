# frozen_string_literal: true

module Balance
  module Upset
    module_function

    # Iteration where the cheaper template won (equal cost is not an upset).
    def duel_counts(runs, units)
      iterations = 0
      upsets = 0

      runs.each do |run|
        left = units[run.left_template]
        right = units[run.right_template]
        next unless left && right

        left_cost = left.cost.to_i
        right_cost = right.cost.to_i
        iters = run.iterations.to_i
        iterations += iters

        if left_cost < right_cost
          upsets += run.left_wins.to_i
        elsif right_cost < left_cost
          upsets += run.right_wins.to_i
        end
      end

      {
        upset_count: upsets,
        upset_rate: DuelRuns.rate(upsets, iterations)
      }
    end
  end
end
