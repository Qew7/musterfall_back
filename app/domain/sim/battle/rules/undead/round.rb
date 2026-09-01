module Sim
  module Battle
    module Rules
      module Undead
        module Round
          # rule: undead | round | While general lives, one random wounded undead unit heals +1 HP per round.
          module_function

          def apply_passives!(side)
            return [] unless side[:faction_id] == "undead"
            return [] unless Undead.general_alive?(side[:combatants])

            rng = side[:rng]
            wounded = wounded_undead_units(side)
            return [] if wounded.empty?

            target = wounded.length == 1 ? wounded.first : wounded[rng.rand(wounded.length)]
            target[:current_health] = [ target[:max_health], target[:current_health] + 1 ].min
            State.sync_combatant_footprint!(target)
            [ "#{side[:player_name]}: #{target[:name]} восстанавливает 1 здоровье." ]
          end

          def wounded_undead_units(side)
            side[:combatants].select do |entry|
              Array(entry[:abilities]).include?("undead") &&
                entry[:current_health].to_i.between?(1, entry[:max_health].to_i - 1)
            end
          end
          private_class_method :wounded_undead_units
        end
      end
    end
  end
end
