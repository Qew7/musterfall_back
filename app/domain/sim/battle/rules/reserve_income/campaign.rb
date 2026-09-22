module Sim
  module Battle
    module Rules
      module ReserveIncome
        module Campaign
          INCOME = 200

          # rule: reserve_income | campaign | Each living company held in reserve for a fought battle adds 200 to its owner's next recruitment allowance; byes pay nothing.
          module_function

          def applies?(profile)
            Array(profile[:abilities]).include?("reserveIncome")
          end

          def income_rewards(side)
            Array(side[:campaign_rewards] || side["campaignRewards"] || side["campaign_rewards"]).filter_map do |entry|
              data = entry.with_indifferent_access
              next unless (data[:rule_key] || data[:ruleKey]) == "reserveIncome"

              { amount: INCOME, name: data[:name], entity_id: data[:entity_id] || data[:entityId] }
            end.uniq { |reward| reward[:entity_id] }
          end

          # A healthy field force can spare the company. With fewer than two
          # other viable units, automatic deployment uses its combat strength.
          def reserve_for_deployment?(profile, roster)
            return false unless applies?(profile)

            roster.count { |entry| entry[:kind] == "unit" && entry[:models].to_i >= 3 && !applies?(entry) } >= 2
          end
        end
      end
    end
  end
end
