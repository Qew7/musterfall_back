module Sim
  module Battle
    # Rule-first overrides: files live at rules/<rule>/<phase>.rb
    # Registry is indexed by phase so Phase.play can apply hooks without knowing rule names.
    module Rules
      module_function

      REGISTRY = {
        melee: -> { [ Fear::Melee ] },
        shooting: -> { [ Breath::Shooting ] },
        movement: -> { [ Flying::Movement ] }
      }.freeze

      def for(phase)
        RuleSet.new(Array(REGISTRY.fetch(phase.to_sym, -> { [] }).call))
      end

      def planner_for_movement(combatant)
        Array(combatant[:abilities]).include?("flying") ? Flying::Movement : Ground::Movement
      end

      class RuleSet
        attr_reader :rules

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
      end
    end
  end
end
