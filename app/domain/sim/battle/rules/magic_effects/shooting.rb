module Sim
  module Battle
    module Rules
      module MagicEffects
        module Shooting
          module_function

          def allow_target?(_attacker, target, attack_type)
            attack_type.to_s != "shooting" ||
              !Sim::Battle::SpellEffects.status?(target, :ranged_hidden)
          end

          def hit_chance_factor(attacker, _defender, attack_type)
            if attack_type.to_s == "shooting" &&
                Sim::Battle::SpellEffects.status?(attacker, :ranged_hindered)
              0.5
            else
              1.0
            end
          end

          def damage_factor(_attacker, defender, attack_type, _vector, _round_number)
            if attack_type.to_s == "magic" &&
                Sim::Battle::SpellEffects.status?(defender, :magic_ward)
              0.5
            else
              1.0
            end
          end
        end
      end
    end
  end
end
