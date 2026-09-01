module Sim
  module Battle
    module SemanticSnapshot
      VERSION = 1
      POSITION_PRECISION = 3

      module_function

      def build(report)
        value = deep_symbolize(report)
        actions = extract_actions(value)
        {
          version: VERSION,
          winner_id: value[:winner_id],
          rounds: Array(value[:rounds]).length,
          side_health: {
            left: side_health(value[:left]),
            right: side_health(value[:right])
          },
          action_counts: actions.group_by { |entry| entry[:type] }
            .transform_values(&:length)
            .sort.to_h,
          contacts: actions.filter_map { |entry| contact_fingerprint(entry) },
          rule_effects: actions.flat_map { |entry| Array(entry.dig(:trace, :rule_keys)) }
            .map { |key| key.to_s.underscore }
            .tally
            .sort.to_h,
          actions: actions.map { |entry| action_fingerprint(entry) }
        }
      end

      def extract_actions(report)
        Array(report[:rounds]).each_with_index.flat_map do |round, round_index|
          Array(round[:turns]).each_with_index.flat_map do |turn, turn_index|
            Array(turn[:phases]).each_with_index.flat_map do |phase, phase_index|
              Array(phase[:actions]).each_with_index.map do |action, action_index|
                deep_symbolize(action).merge(
                  semantic_path: "R#{round_index + 1}/T#{turn_index + 1}/#{phase[:type] || phase[:phase_type]}/A#{action_index + 1}"
                )
              end
            end
          end
        end
      end

      def action_fingerprint(action)
        maneuver = action[:maneuver] || {}
        trace = action[:trace] || {}
        {
          path: action[:semantic_path],
          type: action[:type].to_s,
          actor_id: action[:actor_id],
          target_id: maneuver[:target_id] || action[:target_id] || action.dig(:charge, :target_id),
          from: pose(action[:from]),
          to: pose(action[:to]),
          maneuver: compact_hash(
            kind: maneuver[:kind],
            contact_slot: maneuver[:contact_slot],
            approach_mode: maneuver[:approach_mode],
            truncated: maneuver[:truncated_by_collision],
            avoided: maneuver[:avoided],
            blocked_by_ally: maneuver[:blocked_by_ally]
          ),
          damage: action[:damage] || action[:models_lost],
          spell: action[:spell_key] && compact_hash(
            key: action[:spell_key],
            school: action[:magic_school],
            dice: action[:dice],
            total: action[:casting_total],
            value: action[:casting_value],
            outcome: action[:outcome],
            affected_ids: Array(action[:affected_ids]).sort,
            summon_ids: Array(action[:summon_ids]).sort,
            terrain_delta: action[:terrain_delta]
          ),
          morale: compact_hash(
            roll: action.dig(:check, :roll),
            threshold: action.dig(:check, :threshold),
            passed: action.dig(:check, :passed)
          ),
          trace: compact_hash(
            version: trace[:version],
            rule_keys: Array(trace[:rule_keys]).map(&:to_s).sort,
            result: trace[:result]
          )
        }.compact
      end

      def contact_fingerprint(action)
        maneuver = action[:maneuver] || {}
        kind = maneuver[:kind].to_s
        return nil unless action[:charge] || %w[contact_align flyer_charge].include?(kind)

        {
          actor_id: action[:actor_id],
          target_id: maneuver[:target_id] || action.dig(:charge, :target_id),
          slot: maneuver[:contact_slot],
          kind: kind
        }.compact
      end

      def pose(value)
        return nil unless value.is_a?(Hash) && value.key?(:x) && value.key?(:y)

        {
          x: value[:x].to_f.round(POSITION_PRECISION),
          y: value[:y].to_f.round(POSITION_PRECISION),
          facing: value[:facing].to_f.round(2)
        }
      end

      def side_health(side)
        Array(side && side[:combatants]).sum { |entry| entry[:current_health].to_f }.round(3)
      end

      def compact_hash(value)
        value.reject { |_key, entry| entry.nil? || entry == [] || entry == {} }
      end

      def deep_symbolize(value)
        Sim::Campaign::State.deep_symbolize(value || {})
      end
    end
  end
end
