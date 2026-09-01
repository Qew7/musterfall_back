module Sim
  module Battle
    module Rules
      module ArmorPiercing
        module Melee
          module_function

          def armor_factor(attacker, _defender, _attack_type, factor)
            return factor unless Array(attacker[:abilities]).include?("armorPiercing")

            1.0 + ((factor - 1.0) * 0.5)
          end

          def log_clauses(ctx)
            attacker = ctx[:attacker]
            return [] unless Array(attacker[:abilities]).include?("armorPiercing")

            defender = ctx[:defender]
            base = Constants::WEAPON_VS_ARMOR.dig(defender[:armor_type], attacker[:weapon_type]) || 1
            armor_factor(attacker, defender, ctx[:attack_type], base) == base ? [] : [ "бронебойность" ]
          end
        end
      end
    end
  end
end
