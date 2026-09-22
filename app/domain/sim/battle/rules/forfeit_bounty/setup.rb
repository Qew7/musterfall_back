module Sim
  module Battle
    module Rules
      module ForfeitBounty
        module Setup
          # rule: forfeit_bounty | setup | Announce the full victory-point bounty of each deployed penal company at battle start.
          module_function

          def prepare_side!(side, _player)
            side[:combatants].each do |unit|
              next unless Array(unit[:abilities]).include?("forfeitBounty")

              cost = unit.fetch(:unit_cost, unit[:cost]).to_i
              (side[:setup_actions] ||= []) << {
                type: "rule", actor_id: unit[:entity_id], actor_name: unit[:name],
                summary: "#{unit[:name]}: противник сразу получает #{cost} очков победы по условиям контракта.",
                details: [ "forfeit_bounty cost=#{cost} duplicate_on_death=false" ],
                trace: Trace.build(rule_keys: [ "forfeitBounty" ], trigger: "battle_start", result: "bounty_awarded", target_ids: [ unit[:entity_id] ])
              }
            end
          end
        end
      end
    end
  end
end
