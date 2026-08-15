require "test_helper"

class SimBattleRuleContractTest < ActiveSupport::TestCase
  test "RuleSet composes each, AND, product, sum and first-result hooks" do
    calls = []
    first = rule_module(
      before_play!: ->(ctx) { calls << [ :first, ctx ] },
      allow_attack?: ->(*) { true },
      damage_factor: ->(*) { 1.5 },
      morale_threshold_delta: ->(*) { -1 },
      facing_damage_factor: ->(*) { nil },
      effective_morale: ->(*) { nil },
      apply_passives!: ->(*) { [ "first" ] }
    )
    second = rule_module(
      before_play!: ->(ctx) { calls << [ :second, ctx ] },
      allow_attack?: ->(*) { false },
      damage_factor: ->(*) { 2.0 },
      morale_threshold_delta: ->(*) { 3 },
      facing_damage_factor: ->(*) { 1.25 },
      effective_morale: ->(*) { 8 },
      apply_passives!: ->(*) { [ "second" ] }
    )
    rules = Sim::Battle::Rules::RuleSet.new([ first, second ])

    rules.before_play!(:context)

    assert_equal [ [ :first, :context ], [ :second, :context ] ], calls
    refute rules.allow_attack?({})
    assert_in_delta 3.0, rules.damage_factor({}, {}, :melee, :front, 1), 0.001
    assert_equal 2, rules.morale_threshold_delta({}, [], [], 0)
    assert_in_delta 1.25, rules.facing_damage_factor({}, :front), 0.001
    assert_equal 8, rules.effective_morale({}, [])
    assert_equal %w[first second], rules.apply_passives!({})
  end

  test "RuleSet preserves defaults when no rule implements an optional hook" do
    rules = Sim::Battle::Rules::RuleSet.new([ Module.new ])

    assert rules.allow_attack?({})
    assert rules.requires_front_arc_for_ranged?({})
    assert_in_delta 1.0, rules.damage_factor({}, {}, :melee, :front, 1), 0.001
    assert_equal 0, rules.morale_threshold_delta({}, [], [], 0)
    assert_nil rules.facing_damage_factor({}, :front)
    assert_nil rules.effective_morale({}, [])
    assert_nil rules.handle_morale_failure!({}, {}, {})
    assert_empty rules.apply_passives!({})
  end

  test "movement ability dispatch is observable through the public facade" do
    infantry = BattleScenarios.combatant(movement: 4.0, abilities: [])
    flyer = BattleScenarios.combatant(movement: 10.0, abilities: [ "flying" ])
    machine = BattleScenarios.combatant(movement: 2.0, abilities: [ "machine" ])
    enemy = BattleScenarios.enemy(x: 32.0)

    assert_in_delta 4.0,
                    Sim::Battle::Decisions::Movement.budget_for(infantry, enemies: [ enemy ]),
                    0.001
    assert_in_delta 10.0,
                    Sim::Battle::Decisions::Movement.budget_for(flyer, enemies: [ enemy ]),
                    0.001
    assert_in_delta 2.0,
                    Sim::Battle::Decisions::Movement.budget_for(machine, enemies: [ enemy ]),
                    0.001

    ground_intent = Sim::Battle::Decisions::Movement.build_approach_intent(
      combatant: infantry,
      nearest: enemy,
      obstacles: [ enemy ],
      enemies: [ enemy ]
    )
    flying_intent = Sim::Battle::Decisions::Movement.build_approach_intent(
      combatant: flyer,
      nearest: enemy,
      obstacles: [ enemy ],
      enemies: [ enemy ]
    )

    refute ground_intent.dig(:plan, :leap)
    assert flying_intent.dig(:plan, :leap)
  end

  private

  def rule_module(methods)
    Module.new.tap do |mod|
      methods.each do |name, implementation|
        mod.define_singleton_method(name, &implementation)
      end
    end
  end
end
