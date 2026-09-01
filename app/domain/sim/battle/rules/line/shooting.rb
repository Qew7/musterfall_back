module Sim
  module Battle
    module Rules
      module Line
        module Shooting
          module_function

          def applies?(attacker, attack_type)
            kind = attack_type.to_s == "magic" ? attacker[:spell_template] : attacker[:shooting_template]
            kind.to_s == "line"
          end

          def template(attacker, primary_target)
            Templates::Line.new(attacker, primary_target)
          end

          def attack_victims(attacker, primary_target, enemies)
            template(attacker, primary_target).attack_victims(enemies)
          end

          def template_descriptor(attacker, primary_target, victims)
            template(attacker, primary_target).template_descriptor(victims)
          end

          def resolve_missile_strike!(**ctx)
            template(ctx[:profile], ctx[:primary]).resolve_missile_strike!(**ctx)
          end

          def expected_damage(actor, target, vector, round_number, attack_type, enemies)
            template(actor, target).expected_damage(actor, target, vector, round_number, attack_type, enemies)
          end
        end
      end
    end
  end
end
