module Sim
  module Battle
    module Rules
      module SkySnare
        module Movement
          RANGE = 6.0
          AMMUNITION = 2
          PROVIDER = ->(profile) { Array(profile[:abilities]).include?("skySnare") }
          CONSUMER = ->(profile) { profile[:ranged].to_i.positive? || profile[:spell].to_i.positive? }
          # Coverage of two nearby valuable units is a deployment estimate, not an activation limit.
          SYNERGY = ArmySynergy.new(
            consumer: CONSUMER, provider: PROVIDER,
            capacity: ->(profile) { profile[:models].to_f.positive? ? 2.0 : 0.0 },
            range: ->(_profile) { RANGE }, center_distance: true, required: false,
            benefit: ->(user, _source) { !PROVIDER.call(user) }
          ).freeze

          # rule: sky_snare | movement | Twice per battle, intercept an enemy flight crossing a six-inch zone before contact and force a legal landing without a charge.
          module_function

          def bot_pack_as(profile)
            :ranged if PROVIDER.call(profile)
          end

          def army_synergies
            [ SYNERGY ]
          end

          def prepare_movement_intents!(ctx)
            providers = ctx[:target_side][:combatants].select do |entry|
              PROVIDER.call(entry) && entry[:current_health].to_f.positive? && !entry[:is_routing] &&
                entry[:sky_snare_shots].to_i < AMMUNITION
            end
            return if providers.empty?

            ctx[:intents].each do |intent|
              next if intent[:wait] || !intent[:destination] || !intent.dig(:plan, :leap)
              next unless Array(intent[:combatant][:abilities]).include?("flying")

              candidates = providers.filter_map do |provider|
                next if provider[:sky_snare_shots].to_i >= AMMUNITION

                fraction = interception_fraction(intent[:from], intent[:destination], provider)
                [ provider, fraction ] if fraction
              end.sort_by(&:last)
              candidates.each do |provider, fraction|
                landing = clear_landing(intent, fraction, ctx)
                next unless landing

                intercept!(intent, provider, landing, ctx)
                break
              end
            end
          end

          def interception_fraction(from, to, center)
            dx = to[:x].to_f - from[:x].to_f
            dy = to[:y].to_f - from[:y].to_f
            fx = from[:x].to_f - center[:x].to_f
            fy = from[:y].to_f - center[:y].to_f
            a = dx * dx + dy * dy
            return nil if a < 0.0025
            return 0.0 if fx * fx + fy * fy <= RANGE * RANGE

            b = 2 * (fx * dx + fy * dy)
            c = fx * fx + fy * fy - RANGE * RANGE
            discriminant = b * b - 4 * a * c
            return nil if discriminant.negative?

            entry = (-b - Math.sqrt(discriminant)) / (2 * a)
            entry.between?(0.0, 1.0) ? entry : nil
          end

          def clear_landing(intent, fraction, ctx)
            unit = intent[:combatant]
            from = intent[:from]
            to = intent[:destination]
            combatants = ctx[:acting_side][:combatants] + ctx[:target_side][:combatants]
            other_destinations = ctx[:intents].reject { |other| other.equal?(intent) }.filter_map do |other|
              other[:combatant].merge(other[:destination]) if other[:destination]
            end
            obstacles = Pathing::Obstacles.merge(combatants + other_destinations, Array(ctx[:terrain]))
            # Work back toward the departure point; never drag a flyer through a
            # blocked landing or place it in contact after cancelling its assault.
            25.times do |index|
              t = fraction * (1.0 - index / 24.0)
              pose = unit.merge(
                x: from[:x].to_f + (to[:x].to_f - from[:x].to_f) * t,
                y: from[:y].to_f + (to[:y].to_f - from[:y].to_f) * t,
                facing: from[:facing]
              )
              next unless Flying::Movement.flyer_landing_clear?(pose, obstacles)
              next if ctx[:target_side][:combatants].any? do |enemy|
                enemy[:current_health].to_f.positive? && Geometry::Battlefield.melee_contact?(pose, enemy)
              end

              return pose
            end
            nil
          end

          def intercept!(intent, provider, landing, ctx)
            unit = intent[:combatant]
            from = intent[:from]
            distance = Geometry::Battlefield.distance_between(from, landing)
            motions = distance > 0.05 ? [ Pathing::Maneuvers.motion_entry("advance", from, landing, cost: distance) ] : []
            intent[:destination] = Geometry::Battlefield.footprint_destination(landing)
            intent[:charge_contact_id] = nil
            intent[:free_align] = false
            intent[:plan] = intent[:plan].merge(
              pose: landing, charge: false, sky_snared: true, truncated: true,
              motion_sequence: motions, steps: motions.map { |motion| motion.slice(:kind, :cost) },
              cost_spent: distance, mv_spent_advance: distance, mv_spent_march: 0.0,
              mv_spent_wheel: 0.0, mv_spent_turn: 0.0, wheel: nil, turn: nil
            )
            provider[:sky_snare_shots] = provider[:sky_snare_shots].to_i + 1
            summary = "#{provider[:name]} стягивает #{unit[:name]} с неба: полёт прерван, заряд сорван."
            Phases::AttackResolution.add_event(ctx[:phase], summary)
            ctx[:phase][:actions] << {
              type: "sky_snare", actor_id: provider[:entity_id], actor_name: provider[:name],
              target_id: unit[:entity_id], target_name: unit[:name], damage: 0,
              summary: summary, details: [ "sky_snare range=#{RANGE} ammunition=#{AMMUNITION - provider[:sky_snare_shots]} landing=#{landing[:x]},#{landing[:y]}" ],
              snapshot: State.snapshot_battlefield([ ctx[:acting_side], ctx[:target_side] ]),
              trace: Trace.build(rule_keys: [ "skySnare" ], trigger: "enemy_flight", result: "intercepted", target_ids: [ unit[:entity_id] ])
            }
          end
        end
      end
    end
  end
end
