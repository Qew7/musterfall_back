module Sim
  module Battle
    module Rules
      module TreasuryGuard
        module Setup
          STEP = 200
          MAX_STEPS = 2

          # rule: treasury_guard | setup | Snapshot unspent treasury at battle start: each 200 grants +1 melee and morale, capped at +2 for this battle only.
          module_function

          def applies?(profile)
            Array(profile[:abilities]).include?("treasuryGuard")
          end

          def prepare_side!(side, player)
            treasury = [ player[:treasury].to_i, 0 ].max
            levels = [ treasury / STEP, MAX_STEPS ].min
            side[:combatants].each do |unit|
              next unless applies?(unit)

              unit[:treasury_at_start] = treasury
              unit[:treasury_guard_bonus] = levels
              unit[:melee] += levels
              unit[:morale] += levels
              Array(unit.dig(:contributors, :melee)).each do |contributor|
                contributor[:power] += levels if applies?(contributor)
              end
              (side[:setup_actions] ||= []) << {
                type: "rule", actor_id: unit[:entity_id], actor_name: unit[:name],
                summary: "#{unit[:name]}: в казне #{treasury}; ML +#{levels}, MO +#{levels} до конца боя.",
                details: [ "treasury_guard treasury=#{treasury} step=#{STEP} bonus=#{levels} cap=#{MAX_STEPS}" ],
                trace: Trace.build(rule_keys: [ "treasuryGuard" ], trigger: "battle_start", result: "stats_applied", target_ids: [ unit[:entity_id] ])
              }
            end
          end

          # Planning preference: keep the highest currently affordable threshold,
          # rather than spending the last coins on a weaker marginal purchase.
          def treasury_reserve(profiles, treasury)
            return 0 unless profiles.any? { |profile| applies?(profile) && profile[:models].to_i.positive? }

            [ [ treasury.to_i, 0 ].max / STEP, MAX_STEPS ].min * STEP
          end
        end
      end
    end
  end
end
