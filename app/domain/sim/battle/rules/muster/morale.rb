module Sim
  module Battle
    module Rules
      module Muster
        module Morale
          # rule: muster | morale | Hero muster raises ally effective morale to hero morale within range.
          module_function

          def effective_morale(combatant, allies)
            return nil if combatant[:kind] == "hero"

            sources = muster_sources(allies)
              .select { |source| source[:morale] > combatant[:morale] }
              .select { |source| Geometry::Battlefield.distance_between(combatant, source) <= source[:morale] }
              .sort_by { |source| [ -source[:morale], Geometry::Battlefield.distance_between(combatant, source) ] }
            return nil if sources.empty?

            { value: sources.first[:morale], label: "Muster от #{sources.first[:name]}" }
          end

          def muster_sources(allies)
            sources = []
            allies.each do |combatant|
              if combatant[:kind] == "hero" && Array(combatant[:abilities]).include?("muster")
                sources << {
                  entity_id: combatant[:entity_id],
                  name: combatant[:name],
                  morale: combatant[:morale],
                  x: combatant[:x],
                  y: combatant[:y]
                }
              end

              Array(combatant[:attached_heroes]).each do |hero|
                next unless Array(hero[:abilities]).include?("muster")

                sources << {
                  entity_id: hero[:entity_id],
                  name: hero[:name],
                  morale: hero[:morale],
                  x: combatant[:x],
                  y: combatant[:y]
                }
              end
            end
            sources
          end
          module_function :muster_sources
        end
      end
    end
  end
end
