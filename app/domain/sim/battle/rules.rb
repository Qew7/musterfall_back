module Sim
  module Battle
    # Rule-first overrides: files live at rules/<rule>/<phase>.rb
    # Registry is indexed by phase so Phase.play can apply hooks without knowing rule names.
    module Rules
      module_function

      REGISTRY = {
        melee: -> {
          [
            Fear::Melee,
            Charge::Melee,
            Ferocious::Melee,
            Steadfast::Melee,
            Skirmisher::Melee
          ]
        },
        shooting: -> {
          [
            Breath::Shooting,
            Volley::Shooting,
            Blast::Shooting,
            Machine::Shooting,
            Steadfast::Melee,
            Skirmisher::Melee
          ]
        },
        morale: -> {
          [
            Undead::Morale,
            Fear::Morale,
            Disciplined::Morale,
            Muster::Morale
          ]
        },
        setup: -> { [ BannerAura::Setup, SteadfastAura::Setup ] },
        round: -> { [ Undead::Round ] },
        movement: -> { [ March::Movement, Flying::Movement ] }
      }.freeze

      def for(phase)
        RuleSet.new(Array(REGISTRY.fetch(phase.to_sym, -> { [] }).call))
      end

      def planner_for_movement(combatant)
        Array(combatant[:abilities]).include?("flying") ? Flying::Movement : Ground::Movement
      end

      def damage_phase_for(attack_type)
        attack_type.to_s == "melee" ? :melee : :shooting
      end

      class RuleSet
        attr_reader :rules # leftovers:keep

        def initialize(rules)
          @rules = Array(rules)
        end

        def before_play!(ctx)
          @rules.each do |rule|
            rule.before_play!(ctx) if rule.respond_to?(:before_play!)
          end
        end

        def allow_attack?(attacker, ctx = nil)
          @rules.all? do |rule|
            next true unless rule.respond_to?(:allow_attack?)

            rule.allow_attack?(attacker, ctx)
          end
        end

        def find_applicable(profile, attack_type)
          @rules.find { |rule| rule.respond_to?(:applies?) && rule.applies?(profile, attack_type) }
        end

        # Product of per-rule multipliers (missing hook => 1.0).
        def damage_factor(attacker, defender, attack_type, vector, round_number)
          @rules.reduce(1.0) do |acc, rule|
            next acc unless rule.respond_to?(:damage_factor)

            acc * rule.damage_factor(attacker, defender, attack_type, vector, round_number).to_f
          end
        end

        # First non-nil override; nil means "use AttackResolution default facing".
        def facing_damage_factor(defender, vector)
          @rules.each do |rule|
            next unless rule.respond_to?(:facing_damage_factor)

            value = rule.facing_damage_factor(defender, vector)
            return value unless value.nil?
          end
          nil
        end

        def morale_threshold_delta(combatant, allies, enemies, combat_score_delta)
          @rules.sum do |rule|
            next 0 unless rule.respond_to?(:morale_threshold_delta)

            rule.morale_threshold_delta(combatant, allies, enemies, combat_score_delta).to_i
          end
        end

        def effective_morale(combatant, allies)
          @rules.each do |rule|
            next unless rule.respond_to?(:effective_morale)

            result = rule.effective_morale(combatant, allies)
            return result if result
          end
          nil
        end

        # First rule that returns a Hash wins (e.g. undead HP loss).
        def handle_morale_failure!(combatant, check, ctx)
          @rules.each do |rule|
            next unless rule.respond_to?(:handle_morale_failure!)

            result = rule.handle_morale_failure!(combatant, check, ctx)
            return result if result
          end
          nil
        end

        # AND across rules that vote; if none vote, default true (front arc required).
        def requires_front_arc_for_ranged?(attacker)
          voters = @rules.select { |rule| rule.respond_to?(:requires_front_arc_for_ranged?) }
          return true if voters.empty?

          voters.all? { |rule| rule.requires_front_arc_for_ranged?(attacker) }
        end

        def apply_attach!(host_ctx)
          @rules.each do |rule|
            rule.apply_attach!(host_ctx) if rule.respond_to?(:apply_attach!)
          end
        end

        def apply_passives!(side)
          events = []
          @rules.each do |rule|
            next unless rule.respond_to?(:apply_passives!)

            events.concat(Array(rule.apply_passives!(side)))
          end
          events
        end

        def movement_budget(combatant, ctx = {})
          base = combatant[:movement].to_f
          multiplier = @rules.reduce(1.0) do |acc, rule|
            next acc unless rule.respond_to?(:movement_multiplier)

            acc * rule.movement_multiplier(combatant, ctx).to_f
          end
          base * multiplier
        end

        def movement_budget_meta(combatant, ctx = {})
          meta = {}
          @rules.each do |rule|
            next unless rule.respond_to?(:movement_budget_meta)

            meta.merge!(rule.movement_budget_meta(combatant, ctx))
          end
          meta
        end
      end
    end
  end
end
