module Sim
  module Battle
    module Rules
      module OverheadVolley
        module Shooting
          PROVIDER = ->(profile) { Array(profile[:abilities]).include?("overheadVolley") }
          SCREEN = ->(profile) {
            profile[:kind] == "unit" && (profile[:model_class] == "infantry" ||
              (profile[:model_class].nil? && profile[:model_width].to_f.positive? &&
                profile[:model_width].to_f <= 1.0 && profile[:model_depth].to_f.positive? &&
                profile[:model_depth].to_f <= 1.0))
          }
          SYNERGY = ArmySynergy.new(
            consumer: PROVIDER, provider: SCREEN,
            capacity: ->(profile) { profile[:models].to_f.positive? ? 1.0 : 0.0 },
            range: ->(_profile) { 1.5 }
          ).freeze

          # rule: overhead_volley | shooting | Ignore one allied infantry line-of-sight blocker; further units and terrain still block the shot.
          module_function

          def army_synergies
            [ SYNERGY ]
          end

          def bot_pack_as(profile)
            :ranged if PROVIDER.call(profile)
          end

          def filter_line_of_sight_blockers(attacker, _target, blockers)
            return blockers unless PROVIDER.call(attacker)

            screen = blockers.find do |blocker|
              SCREEN.call(blocker) && Decisions::Targeting.same_side?(attacker, blocker)
            end
            screen ? blockers.reject { |blocker| blocker.equal?(screen) } : blockers
          end

          def log_clauses(ctx)
            return [] unless ctx[:attack_type] == "shooting" && PROVIDER.call(ctx[:attacker])

            [ "навесной залп поверх одного союзного пехотного строя" ]
          end
        end
      end
    end
  end
end
