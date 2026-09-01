module Sim
  module Battle
    module Rules
      module SupportRank
        module Melee
          module_function

          def attacking_model_count(attacker, _defender, contact_side, count)
            return count unless contact_side.to_s == "front"
            return count unless Array(attacker[:abilities]).include?("supportRank")

            [ count * 2, attacker[:models_remaining].to_i ].min
          end

          def log_clauses(ctx)
            attacker = ctx[:host] || ctx[:attacker]
            return [] unless ctx[:contact_side].to_s == "front"
            return [] unless Array(attacker[:abilities]).include?("supportRank")
            return [] unless attacker[:models_remaining].to_i > attacker[:files].to_i

            [ "второй ряд бьёт" ]
          end
        end
      end
    end
  end
end
