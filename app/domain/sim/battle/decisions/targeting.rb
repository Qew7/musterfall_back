module Sim
  module Battle
    module Decisions
      # Target selection policy for melee and missile attacks.
      module Targeting
        CONTACT = Geometry::Battlefield::CONFIG[:melee_contact_tolerance]
        CONTACT_SNAP = Geometry::Battlefield::CONFIG[:contact_snap]
        ENGAGE = CONTACT + CONTACT_SNAP

        module_function

        def choose_target(attacker, enemies, attack_type, all_combatants, terrain: [])
          living = enemies.select { |entry| entry[:current_health].to_i > 0 }
          return nil if living.empty?

          if attack_type == "melee"
            engaged = living
              .map { |target| { target: target, distance: Geometry::Battlefield.distance_between_units(attacker, target), vector: Geometry::Battlefield.classify_attack_vector(attacker, target) } }
              .select { |entry| entry[:distance] <= ENGAGE }
              .sort_by { |entry| [ entry[:distance], vector_priority(entry[:vector]) ] }
            return nil if engaged.empty?

            return { target: engaged.first[:target], vector: engaged.first[:vector] }
          end

          # Shooting and magic both refuse units locked in enemy melee.
          available = living.select { |target| can_target_missile?(attacker, target, attack_type, all_combatants, terrain: terrain) }
          return nil if available.empty?

          prioritized = prioritize_routing(available)
          same_lane = Constants::BATTLE_ROWS.flat_map { |row| prioritized.select { |entry| entry[:lane] == attacker[:lane] && entry[:row] == row } }
          if same_lane.any?
            target = same_lane.first
            return { target: target, vector: target[:row] == "front" ? "front" : "rear" }
          end

          adjacent = Constants::LANE_ORDER.reject { |lane| lane == attacker[:lane] }.flat_map do |lane|
            Constants::BATTLE_ROWS.flat_map { |row| prioritized.select { |entry| entry[:lane] == lane && entry[:row] == row } }
          end
          return { target: adjacent.first, vector: "flank" } if adjacent.any?

          { target: prioritized.first, vector: "front" }
        end

        def can_target_missile?(attacker, target, attack_type, all_combatants, terrain: [])
          return false if in_melee_combat?(target, all_combatants)
          return false unless Rules.for(:shooting).allow_target?(attacker, target, attack_type)
          return in_spell_range?(attacker, target) if attack_type.to_s == "magic"

          can_target_ranged?(attacker, target, all_combatants, terrain: terrain)
        end

        # Same metric as SpellContext: center distance, range <= 0 is unlimited.
        def in_spell_range?(attacker, target, range: nil)
          range = attacker[:spell_range].to_f if range.nil?
          range <= 0 || Geometry::Battlefield.distance_between(attacker, target) <= range
        end

        def can_target_ranged?(attacker, target, all_combatants, terrain: [])
          range = attacker[:shooting_range].to_f
          return false if range.positive? && Geometry::Battlefield.distance_between(attacker, target) > range

          if Rules.for(:shooting).requires_front_arc_for_ranged?(attacker) &&
              !Geometry::Battlefield.in_front_arc?(attacker, target, attacker[:facing])
            return false
          end
          return false if in_melee_combat?(target, all_combatants)

          Geometry::Battlefield.line_of_sight_blockers(attacker, target, all_combatants, terrain: terrain).empty?
        end

        # Locked in combat = footprint contact with a living enemy (allies do not count).
        def in_melee_combat?(unit, all_combatants)
          ux = unit[:x].to_f
          uy = unit[:y].to_f
          all_combatants.any? do |entry|
            next false if entry[:entity_id] == unit[:entity_id]
            next false if entry[:current_health].to_i <= 0
            next false if same_side?(unit, entry)

            dx = ux - entry[:x].to_f
            dy = uy - entry[:y].to_f
            # CONTACT + generous diagonal pad; skip OBB when clearly far.
            next false if ((dx * dx) + (dy * dy)) > 36.0

            Geometry::Battlefield.distance_between_units(unit, entry) <= ENGAGE
          end
        end

        def same_side?(left, right)
          return false if left[:side_index].nil? || right[:side_index].nil?

          left[:side_index] == right[:side_index]
        end

        def melee_contact?(unit, all_combatants)
          in_melee_combat?(unit, all_combatants)
        end

        def vector_priority(vector)
          { "rear" => 0, "flank" => 1 }.fetch(vector, 2)
        end

        def prioritize_routing(targets)
          targets.sort_by { |entry| entry[:is_routing] ? 0 : 1 }
        end
      end
    end
  end
end
