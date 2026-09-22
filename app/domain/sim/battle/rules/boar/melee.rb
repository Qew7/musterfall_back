module Sim
  module Battle
    module Rules
      module Boar
        module Melee
          # rule: boar_charge | melee | Flank/rear boarCharge marks ferocious allies in contact with target for +1 melee that round.
          module_function

          CONSUMER = ->(profile) { Array(profile[:abilities]).include?("ferocious") }
          PROVIDER = ->(profile) { Array(profile[:abilities]).include?("boarCharge") }
          # One flanking regiment can usually help one or two friendly regiments
          # fighting the same target; this is a planning estimate, not an aura.
          SYNERGY = ArmySynergy.new(
            consumer: CONSUMER, provider: PROVIDER,
            capacity: ->(_profile) { 2.0 }, range: ->(profile) { [ profile[:movement].to_f, 3.0 ].max }
          ).freeze

          def army_synergies
            [ SYNERGY ]
          end

          def bot_pack_as(profile)
            :flanker if PROVIDER.call(profile)
          end

          def before_play!(ctx)
            sides = [ ctx[:acting_side], ctx[:target_side] ]
            sides.each_with_index do |side, index|
              enemies = sides[1 - index][:combatants]
              side[:combatants].each do |boar|
                next unless PROVIDER.call(boar)
                next unless %w[flank rear].include?(boar[:charged_vector].to_s)

                target = enemies.find { |enemy| enemy[:entity_id] == boar[:charged_target_id] }
                next unless target

                side[:combatants].each do |ally|
                  next unless CONSUMER.call(ally)
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
