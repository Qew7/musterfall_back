module Sim
  module Battle
    module Rules
      module ReserveIncome
        module Setup
          # rule: reserve_income | setup | Record living reserve companies before combat so only companies that sat out this battle earn the next allowance.
          module_function

          def prepare_side!(side, player)
            rewards = Array(player[:roster]).filter_map do |entity|
              next unless Campaign.applies?(abilities: entity.dig(:components, :abilities))
              next unless entity.dig(:state, :current_health).to_i.positive?
              next unless entity.dig(:components, :formation, :row) == "reserve"

              { rule_key: "reserveIncome", entity_id: entity[:id], name: entity[:name], amount: Campaign::INCOME }
            end
            return if rewards.empty?

            side[:campaign_rewards] = rewards
            rewards.each do |reward|
              (side[:setup_actions] ||= []) << {
                type: "rule", actor_id: reward[:entity_id], actor_name: reward[:name],
                summary: "#{reward[:name]} работают в резерве: после боя +#{Campaign::INCOME} к следующему найму.",
                details: [ "reserve_income amount=#{Campaign::INCOME} timing=next_recruitment" ],
                trace: Trace.build(rule_keys: [ "reserveIncome" ], trigger: "battle_start", result: "reserve_recorded", target_ids: [ reward[:entity_id] ])
              }
            end
          end
        end
      end
    end
  end
end
