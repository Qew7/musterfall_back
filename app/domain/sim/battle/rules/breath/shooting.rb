module Sim
  module Battle
    module Rules
      module Breath
        # Breath weapon overrides for the shooting (missile) phase.
        # Fixed 8" teardrop; models whose center is under the template are hit (auto-hit).
        module Shooting
          # rule: breath | shooting | Teardrop template; auto-hits models under the shape.
          module_function

          def applies?(attacker, attack_type)
            kind = attack_type == "magic" ? attacker[:spell_template] : attacker[:shooting_template]
            kind.to_s == "breath"
          end

          def template(attacker, primary_target)
            Templates::Breath.new(attacker, primary_target)
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
