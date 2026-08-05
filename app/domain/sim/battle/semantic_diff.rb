module Sim
  module Battle
    module SemanticDiff
      module_function

      def call(stored, fresh)
        left = SemanticSnapshot.build(stored)
        right = SemanticSnapshot.build(fresh)
        {
          identical: left == right,
          winner_changed: left[:winner_id] != right[:winner_id],
          categories_changed: changed_categories(left, right),
          first_divergence: first_divergence(left, right),
          stored: left,
          fresh: right
        }
      end

      def changed_categories(left, right)
        %i[winner_id rounds side_health action_counts contacts rule_effects actions].select do |key|
          left[key] != right[key]
        end
      end

      def first_divergence(left, right)
        %i[winner_id rounds side_health action_counts contacts rule_effects].each do |key|
          next if left[key] == right[key]

          return { path: key.to_s, stored: left[key], fresh: right[key] }
        end

        max = [ left[:actions].length, right[:actions].length ].max
        max.times do |index|
          stored_action = left[:actions][index]
          fresh_action = right[:actions][index]
          next if stored_action == fresh_action

          return action_divergence(index, stored_action, fresh_action)
        end
        nil
      end

      def action_divergence(index, stored, fresh)
        return { path: "actions[#{index}]", stored: stored, fresh: fresh } unless stored && fresh

        key = (stored.keys | fresh.keys).find { |candidate| stored[candidate] != fresh[candidate] }
        {
          path: "#{stored[:path] || fresh[:path] || "actions[#{index}]"}.#{key}",
          stored: stored[key],
          fresh: fresh[key]
        }
      end
    end
  end
end
