module Sim
  module Battle
    module Rules
      module BanishSummons
        module Round
          RANGE = 4.0
          DAMAGE = 4

          # rule: banish_summons | round | At round end, each living unrouted provider deals four damage to enemy summoned units within four inches.
          module_function

          def bot_pack_as(profile)
            :frontline if Array(profile[:abilities]).include?("banishSummons")
          end

          def after_play!(ctx)
            sides = ctx.fetch(:sides)
            sides.each do |side|
              foes = sides.reject { |other| other.equal?(side) }.flat_map { |other| other[:combatants] }
              side[:combatants].each do |source|
                next unless Array(source[:abilities]).include?("banishSummons")
                next unless source[:current_health].to_f.positive? && !source[:is_routing]

                foes.each do |target|
                  next unless target[:summoned] && target[:current_health].to_f.positive?
                  next if Geometry::Battlefield.distance_between_units(source, target) > RANGE

                  before = State.snapshot_combatant(target)
                  damage = [ DAMAGE, target[:current_health].to_i ].min
                  target[:current_health] -= damage
                  State.sync_combatant_footprint!(target)
                  summary = "#{source[:name]} изгоняет призванных #{target[:name]}: #{damage} урона."
                  Phases::AttackResolution.add_event(ctx[:phase], summary)
                  ctx[:phase][:actions] << {
                    type: "banish_summons", actor_id: source[:entity_id], actor_name: source[:name],
                    target_id: target[:entity_id], target_name: target[:name], damage: damage,
                    summary: summary, details: [ "banish_summons range=#{RANGE} damage=#{damage} summoned=true" ],
                    target_state_before: before, target_state_after: State.snapshot_combatant(target),
                    snapshot: State.snapshot_battlefield(sides),
                    trace: Trace.build(rule_keys: [ "banishSummons" ], trigger: "end_round", result: "damage", target_ids: [ target[:entity_id] ])
                  }
                end
              end
            end
          end
        end
      end
    end
  end
end
