module Sim
  module Battle
    module Rules
      module Undead
        module_function

        def general_alive?(combatants)
          Array(combatants).any? do |entry|
            next false if entry[:current_health].to_i <= 0
            next true if entry[:is_general]

            Array(entry[:attached_heroes]).any? { |hero| hero[:general] }
          end
        end
      end
    end
  end
end
