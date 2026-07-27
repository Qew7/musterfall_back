module Sim
  module Battle
    module Rules
      module Undead
        module Round
          module_function

          def apply_passives!(side)
            return [] unless side[:faction_id] == "undead"

            wounded = side[:combatants].find { |entry| entry[:current_health].to_i > 0 && entry[:current_health] < entry[:max_health] }
            return [] unless wounded

            wounded[:current_health] = [ wounded[:max_health], wounded[:current_health] + 1 ].min
            State.sync_combatant_footprint!(wounded)
            [ "#{side[:player_name]}: #{wounded[:name]} восстанавливает 1 здоровье." ]
          end
        end
      end
    end
  end
end
