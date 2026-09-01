module Sim
  module Battle
    module Rules
      module Ferocious
        module Melee
          module_function

          def before_play!(ctx)
            sides = [ ctx[:acting_side], ctx[:target_side] ]
            sides.each_with_index do |side, index|
              enemies = sides[1 - index][:combatants]
              side[:combatants].each { |combatant| update_streak!(combatant, enemies, ctx[:round_number]) }
            end
          end

          def prepare_profile(profile, host, _defender, attack_type)
            return profile unless attack_type.to_s == "melee"
            return profile unless Array(host[:abilities]).include?("ferocious")

            bonus = host[:ferocious_streak].to_i + host[:ferocious_boar_bonus].to_i
            profile.merge(skill: [ profile[:skill].to_i + bonus, 6 ].min)
          end

          def log_clauses(ctx)
            host = ctx[:host] || ctx[:attacker]
            return [] unless ctx[:attack_type].to_s == "melee"
            return [] unless Array(host[:abilities]).include?("ferocious")

            streak = host[:ferocious_streak].to_i
            boar = host[:ferocious_boar_bonus].to_i
            bonus = streak + boar
            return [] if bonus <= 0

            label = "ярость SK +#{bonus}"
            label += ", кабаний обход" if boar.positive?
            [ label ]
          end

          def update_streak!(combatant, enemies, round_number)
            combatant.delete(:ferocious_boar_bonus)
            return unless Array(combatant[:abilities]).include?("ferocious")

            target = Array(enemies).find do |enemy|
              enemy[:current_health].to_i > 0 &&
                Geometry::Battlefield.distance_between_units(combatant, enemy) <=
                  Geometry::Battlefield::CONFIG[:melee_contact_tolerance] + Geometry::Battlefield::CONFIG[:contact_snap]
            end
            unless target
              combatant.delete(:ferocious_target_id)
              combatant.delete(:ferocious_streak)
              combatant.delete(:ferocious_round)
              return
            end

            if combatant[:ferocious_target_id] == target[:entity_id]
              previous = combatant[:ferocious_round].to_i
              combatant[:ferocious_streak] = combatant[:ferocious_streak].to_i + 1 if round_number.to_i > previous
            else
              combatant[:ferocious_target_id] = target[:entity_id]
              combatant[:ferocious_streak] = 0
            end
            combatant[:ferocious_round] = round_number.to_i
          end
          private_class_method :update_streak!
        end
      end
    end
  end
end
