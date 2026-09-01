module Sim
  module Battle
    module Rules
      module Boar
        module Melee
          # rule: boar_charge | melee | Flank/rear boarCharge marks ferocious allies in contact with target for +1 melee that round.
          module_function

          def before_play!(ctx)
            sides = [ ctx[:acting_side], ctx[:target_side] ]
            sides.each_with_index do |side, index|
              enemies = sides[1 - index][:combatants]
              side[:combatants].each do |boar|
                next unless Array(boar[:abilities]).include?("boarCharge")
                next unless %w[flank rear].include?(boar[:charged_vector].to_s)

                target = enemies.find { |enemy| enemy[:entity_id] == boar[:charged_target_id] }
                next unless target

                side[:combatants].each do |ally|
                  next unless Array(ally[:abilities]).include?("ferocious")
                  next unless Geometry::Battlefield.distance_between_units(ally, target) <=
                    Geometry::Battlefield::CONFIG[:melee_contact_tolerance] + Geometry::Battlefield::CONFIG[:contact_snap]

                  ally[:ferocious_boar_bonus] = 1
                end
              end
            end
          end
        end
      end
    end
  end
end
