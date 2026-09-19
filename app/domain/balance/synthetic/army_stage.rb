module Balance
  module Synthetic
    module ArmyStage
      PRESETS = {
        "early" => { tiers: %w[line], access: 0, budgets: [ 500, 625, 750 ], hero_level: 1, round: 2 },
        "mid" => { tiers: %w[line elite], access: 2, budgets: [ 750, 875, 1000 ], hero_level: 2, round: 3 },
        "late" => { tiers: %w[line elite rare], access: 3, budgets: [ 1000, 1500, 2000 ], hero_level: 3, round: 5 }
      }.freeze
      OPTIONS = [ "mixed", *PRESETS.keys, "custom" ].freeze
      MAX_ROSTER_SIZE = 12

      module_function

      def resolve(config, battle_no:)
        requested = config[:army_stage].to_s
        return config unless OPTIONS.include?(requested) && requested != "custom"

        index = battle_no.to_i
        key = requested == "mixed" ? PRESETS.keys[index % PRESETS.size] : requested
        preset = PRESETS.fetch(key)
        budget_index = requested == "mixed" ? index / PRESETS.size : index
        config.merge(
          army_stage: key, recruit_tiers: preset[:tiers], recruit_access: preset[:access],
          budget_mode: "fixed", target_points: preset[:budgets][budget_index % preset[:budgets].size],
          hero_level: preset[:hero_level], randomize_hero_level: false, round: preset[:round]
        )
      end
    end
  end
end
