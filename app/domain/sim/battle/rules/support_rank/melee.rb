module Sim
  module Battle
    module Rules
      module SupportRank
        module Melee
          module_function

          def attacking_model_count(attacker, _defender, contact_side, count)
            return count unless contact_side.to_s == "front"
            return count unless support_rank_active?(attacker)

            [ count * 2, attacker[:models_remaining].to_i ].min
          end

          def log_clauses(ctx)
            attacker = ctx[:host] || ctx[:attacker]
            return [] unless ctx[:contact_side].to_s == "front"
            return [] unless support_rank_active?(attacker)

            [ "второй ряд бьёт" ]
          end

          def support_rank_active?(attacker)
            Array(attacker[:abilities]).include?("supportRank") && attacker[:ranks].to_i > 1
          end
          private_class_method :support_rank_active?
        end
      end
    end
  end
end
