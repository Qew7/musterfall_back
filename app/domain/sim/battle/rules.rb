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
            SupportRank::Melee,
            Shieldwall::Melee,
            AntiLarge::Melee,
            ArmorPiercing::Melee,
            Dodge::Melee,
            Poison::Melee,
            Toxin::Melee,
            RuneArmor::Melee,
            MomentumCharge::Melee,
            Boar::Melee,
            Skirmisher::Melee,
            Forestkin::Melee,
            MagicEffects::Melee
          ]
        },
        shooting: -> {
          [
            SlingCatapult::Shooting,
            CorpseTrail::Shooting,
            Line::Shooting,
            Breath::Shooting,
            Volley::Shooting,
            Common::Shooting,
            Blast::Shooting,
            Machine::Shooting,
            AntiFlying::Shooting,
            ArmorPiercing::Shooting,
            Dodge::Shooting,
            Toxin::Shooting,
            RuneArmor::Shooting,
            Forestborn::Shooting,
            Skirmisher::Melee,
            MagicEffects::Shooting
          ]
        },
        morale: -> {
          [
            Undead::Morale,
            Fear::Morale,
            Wildborn::Morale,
            Disciplined::Morale,
            Resolute::Morale,
            Muster::Morale
          ]
        },
        setup: -> { [ BannerAura::Setup, ResoluteAura::Setup ] },
        round: -> { [ LavaSpit::Round, Undead::Round, Regen::Round, Forestkin::Round ] },
        turn: -> { [ MagicEffects::Turn ] },
        movement: -> {
          [
            Fear::Movement,
            March::Movement,
            Flying::Movement,
            Wizard::Movement,
            Outrider::Movement,
            Forestborn::Movement,
            Wildborn::Movement,
            ThrowRocks::Movement,
            CorpseTrail::Movement,
            MagicEffects::Movement
          ]
        }
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

        def prepare_melee_intents!(ctx)
          @rules.each do |rule|
            rule.prepare_melee_intents!(ctx) if rule.respond_to?(:prepare_melee_intents!)
          end
        end

        def after_play!(ctx)
          @rules.each do |rule|
            rule.after_play!(ctx) if rule.respond_to?(:after_play!)
          end
        end

        def after_hit!(ctx)
          @rules.each do |rule|
            rule.after_hit!(ctx) if rule.respond_to?(:after_hit!)
          end
        end

        def log_clauses(ctx)
          @rules.flat_map do |rule|
            next [] unless rule.respond_to?(:log_clauses)

            Array(rule.log_clauses(ctx))
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

        def morale_threshold_delta(combatant, allies, enemies, combat_score_delta, terrain: [])
          @rules.sum do |rule|
            next 0 unless rule.respond_to?(:morale_threshold_delta)

            rule.morale_threshold_delta(combatant, allies, enemies, combat_score_delta, terrain: terrain).to_i
          end
        end

        def fearless?(combatant, terrain: [])
          @rules.any? do |rule|
            rule.respond_to?(:fearless?) && rule.fearless?(combatant, terrain: terrain)
          end
        end

        def can_charge_through_terrain?(attacker, defender, terrain)
          @rules.any? do |rule|
            rule.respond_to?(:can_charge_through_terrain?) &&
              rule.can_charge_through_terrain?(attacker, defender, terrain)
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

        def allow_target?(attacker, target, attack_type)
          @rules.all? do |rule|
            !rule.respond_to?(:allow_target?) || rule.allow_target?(attacker, target, attack_type)
          end
        end

        def hit_chance_factor(attacker, defender, attack_type)
          @rules.reduce(1.0) do |factor, rule|
            next factor unless rule.respond_to?(:hit_chance_factor)

            factor * rule.hit_chance_factor(attacker, defender, attack_type).to_f
          end
        end

        def shooting_skill(attacker, defender, terrain, skill)
          @rules.reduce(skill.to_i) do |value, rule|
            next value unless rule.respond_to?(:shooting_skill)

            rule.shooting_skill(attacker, defender, terrain, value).to_i
          end
        end

        def armor_factor(attacker, defender, attack_type, factor)
          @rules.reduce(factor.to_f) do |value, rule|
            next value unless rule.respond_to?(:armor_factor)

            rule.armor_factor(attacker, defender, attack_type, value).to_f
          end
        end

        def attacking_model_count(attacker, defender, contact_side, count)
          @rules.reduce(count.to_i) do |value, rule|
            next value unless rule.respond_to?(:attacking_model_count)

            rule.attacking_model_count(attacker, defender, contact_side, value).to_i
          end
        end

        def prepare_profile(profile, host, defender, attack_type)
          @rules.reduce(profile) do |value, rule|
            next value unless rule.respond_to?(:prepare_profile)

            rule.prepare_profile(value, host, defender, attack_type)
          end
        end

        def terrain_damage_factor(combatant, feature)
          @rules.reduce(1.0) do |factor, rule|
            next factor unless rule.respond_to?(:terrain_damage_factor)

            factor * rule.terrain_damage_factor(combatant, feature).to_f
          end
        end

        def reposition_mode(combatant, ctx)
          @rules.each do |rule|
            next unless rule.respond_to?(:reposition_mode)

            mode = rule.reposition_mode(combatant, ctx)
            return mode if mode
          end
          nil
        end

        def melee_mover?(combatant)
          @rules.each do |rule|
            next unless rule.respond_to?(:melee_mover?)

            result = rule.melee_mover?(combatant)
            return result unless result.nil?
          end
          nil
        end

        def reposition_goals(combatant, mode, ctx)
          @rules.each do |rule|
            next unless rule.respond_to?(:reposition_goals)

            goals = rule.reposition_goals(combatant, mode, ctx)
            return goals if goals
          end
          nil
        end

        def reposition_improves?(origin, candidate, mode, ctx)
          @rules.each do |rule|
            next unless rule.respond_to?(:reposition_improves?)

            result = rule.reposition_improves?(origin, candidate, mode, ctx)
            return result unless result.nil?
          end
          nil
        end

        def apply_attach!(host_ctx)
          @rules.each do |rule|
            rule.apply_attach!(host_ctx) if rule.respond_to?(:apply_attach!)
          end
        end

        def apply_passives!(side, enemy_side: nil)
          ctx = side.merge(enemy_side: enemy_side)
          events = []
          @rules.each do |rule|
            next unless rule.respond_to?(:apply_passives!)

            events.concat(Array(rule.apply_passives!(ctx)))
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
