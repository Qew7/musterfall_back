require "test_helper"

class SimBattleNeutralSupportRulesTest < ActiveSupport::TestCase
  Rules = Sim::Battle::Rules
  Attack = Sim::Battle::Phases::AttackResolution

  test "support rules and their placement contracts are discovered through the registry" do
    assert_includes Rules.for(:melee).rules, Rules::BodyguardContract::Melee
    assert_includes Rules.for(:shooting).rules, Rules::BodyguardContract::Shooting
    assert_includes Rules.for(:shooting).rules, Rules::QuarryMark::Shooting
    assert_includes Rules.for(:morale).rules, Rules::OrderlyRetreat::Morale
    assert_includes Rules.army_synergies, Rules::OverheadVolley::Shooting::SYNERGY
    assert_includes Rules.army_synergies, Rules::BodyguardContract::Melee::SYNERGY
  end

  test "guards transfer at most three damage once with no armor mitigation and no loss of damage" do
    attacker = shooter(ranged: 8)
    target = BattleScenarios.enemy(x: 16)
    guard = BattleScenarios.enemy(entity_id: "guard", x: 16, y: 15, abilities: [ "bodyguardContract", "runeArmor" ], armor_type: "heavy")
    plain = target.deep_dup
    shot(attacker.deep_dup, [ plain ])
    phase = shot(attacker, [ target, guard ])
    assert_equal 5, guard[:current_health]
    assert guard[:bodyguard_contract_used]
    assert_equal 8 - plain[:current_health], (8 - target[:current_health]) + (8 - guard[:current_health])
    assert phase[:actions].any? { |action| Array(action[:details]).any? { |text| text.include?("bodyguard_contract") } }
    shot(attacker, [ target, guard ]) if target[:current_health].positive?
    assert_equal 5, guard[:current_health]
  end

  test "a wounded guard cannot absorb more health than it has and never protects itself" do
    attacker = shooter
    target = BattleScenarios.enemy(x: 16)
    guard = BattleScenarios.enemy(entity_id: "guard", x: 16, y: 15, current_health: 1, abilities: [ "bodyguardContract" ])
    ctx = damage_context(attacker, target, guard, damage: 5)
    Rules.for(:melee).before_damage!(ctx)
    assert_equal 4, ctx[:damage]
    assert_equal 0, guard[:current_health]
    guard[:current_health] = 8
    guard.delete(:bodyguard_contract_used)
    self_ctx = damage_context(attacker, guard, guard, damage: 5)
    Rules.for(:melee).before_damage!(self_ctx)
    assert_equal 5, self_ctx[:damage]
    refute guard[:bodyguard_contract_used]
  end

  test "routing distant and dead guards cannot intercept an attack" do
    attacker = shooter
    target = BattleScenarios.enemy(x: 16)
    [ { is_routing: true }, { x: 30 }, { current_health: 0 } ].each do |overrides|
      guard = BattleScenarios.enemy(entity_id: "guard", x: 16, y: 15, abilities: [ "bodyguardContract" ], **overrides)
      ctx = damage_context(attacker, target, guard, damage: 5)
      Rules.for(:shooting).before_damage!(ctx)
      assert_equal 5, ctx[:damage]
      refute guard[:bodyguard_contract_used]
    end
  end

  test "direct damage spells also route through the damage hook and log the guard action" do
    attacker = shooter
    target = BattleScenarios.enemy(x: 16)
    guard = BattleScenarios.enemy(entity_id: "guard", x: 16, y: 15, abilities: [ "bodyguardContract" ])
    phase = Attack.create_phase("magic", "Магия")
    context = Sim::Battle::SpellContext.new(
      caster: attacker, host: attacker, acting_side: side(attacker), target_side: side(target, guard),
      terrain: [], rng: dice(0.0), round_number: 1,
      spell: Sim::Battle::Spells.fetch(:fireball), phase: phase
    )
    context.damage!(target, power: 10, type: "fire")
    assert guard[:bodyguard_contract_used]
    assert_operator guard[:current_health], :<, 8
    assert phase[:actions].any? { |action| action[:protected_id] == target[:entity_id] }
  end

  test "overhead shots pass one allied infantry screen but not two screens enemies or terrain" do
    attacker = shooter(abilities: [ "overheadVolley" ], requires_line_of_sight: true)
    target = BattleScenarios.enemy(x: 20)
    screen = BattleScenarios.combatant(entity_id: "screen", x: 10, model_class: "infantry")
    second = BattleScenarios.combatant(entity_id: "screen2", x: 14, model_class: "infantry")
    targeting = Sim::Battle::Decisions::Targeting
    assert_empty targeting.line_of_sight_blockers(attacker, target, [ attacker, screen, target ])
    assert_equal 1, targeting.line_of_sight_blockers(attacker, target, [ attacker, screen, second, target ]).size
    assert_equal 1, targeting.line_of_sight_blockers(attacker, target, [ attacker, screen.merge(side_index: 1), target ]).size
    house = BattleScenarios.terrain(x: 14, width: 2, depth: 2)
    refute_empty targeting.line_of_sight_blockers(attacker, target, [ attacker, screen, target ], terrain: [ house ])
    refute_empty targeting.line_of_sight_blockers(attacker.merge(abilities: []), target, [ attacker, screen, target ])
  end

  test "marks are finite successful volleys and cannot be stacked or spent by their source" do
    source = shooter(abilities: [ "quarryMark" ], ranged: 1)
    target = BattleScenarios.enemy(x: 16, current_health: 80, max_health: 80, model_health: 10)
    shot(source, [ target ])
    assert_equal 1, source[:quarry_marks_used]
    mark = target[:quarry_mark].dup
    shot(source, [ target ])
    assert_equal mark, target[:quarry_mark]
    assert_equal 2, source[:quarry_marks_used]
    target.delete(:quarry_mark)
    shot(source, [ target ])
    assert_nil target[:quarry_mark]
    assert_equal 2, source[:quarry_marks_used]
  end

  test "a mark lets a different allied volley reroll exactly its first miss" do
    ally = shooter(entity_id: "other", ranged: 2)
    target = BattleScenarios.enemy(x: 16, quarry_mark: { source_id: "marker", side_index: 0 })
    rng = dice(0.99, 0.0, 0.99)
    phase = shot(ally, [ target ], rng: rng)
    assert_equal 3, rng.calls
    assert_nil target[:quarry_mark]
    attack = phase[:actions].find { |action| action[:type] == "shooting" }
    assert_equal 2, attack[:attacks_attempted]
    assert_equal 1, attack[:hits_landed]
    assert phase[:actions].any? { |action| Array(action[:details]).any? { |line| line.include?("result=reroll") } }
    assert_in_delta 0.5, Rules::Common::Shooting.expected_volley_damage(2, 0.5, 0.6, 8, rerolls: 1), 0.0001
  end

  test "an enemy cannot use a mark and a missed volley cannot place one" do
    source = shooter(abilities: [ "quarryMark" ])
    target = BattleScenarios.enemy(x: 16)
    shot(source, [ target ], rng: dice(0.99))
    assert_nil target[:quarry_mark]
    assert_nil source[:quarry_marks_used]
    mark = { source_id: "other", side_index: 1 }
    refute Rules::QuarryMark::Melee.usable_mark?(source, mark)
  end

  test "first failed melee check withdraws legally with its facing and the next failure routes" do
    unit = retreat_unit
    foe = BattleScenarios.enemy(x: 8, current_health: 4, max_health: 4, models_remaining: 4, starting_models: 4)
    foe.merge!(Sim::Geometry::Battlefield.charge_destination(foe, unit))
    assert Sim::Geometry::Battlefield.melee_contact?(unit, foe)
    action = morale_action(unit, [ foe ])
    refute action[:morale_check][:passed]
    refute unit[:is_routing]
    assert_in_delta 5, unit[:x], 0.01
    assert_equal 0, unit[:facing]
    assert_equal "orderly_retreat", action.dig(:trace, :result)
    assert action[:details].any? { |line| line.include?("orderly_retreat") }
    second = morale_action(unit, [ foe ])
    assert unit[:is_routing] || second[:morale_check][:escaped]
  end

  test "blocked first withdrawal is spent and fear or shooting failures cannot use it" do
    unit = retreat_unit
    blocker = BattleScenarios.combatant(entity_id: "blocker", x: 3.8, current_health: 4, max_health: 4)
    rule = Rules::OrderlyRetreat::Morale
    assert_nil rule.handle_morale_failure!(unit, {}, phase_type: "melee", allies: [ unit, blocker ], enemies: [], terrain: [])
    assert unit[:orderly_retreat_used]
    %w[start shooting movement].each do |phase|
      fresh = retreat_unit
      assert_nil rule.handle_morale_failure!(fresh, {}, phase_type: phase, allies: [ fresh ], enemies: [])
      refute fresh[:orderly_retreat_used]
    end
  end

  test "autopacking places overhead archers close to a legal infantry screen" do
    Sim::Catalog::Loader.reset!
    factory = Sim::Entities::Factory.new(Sim::Catalog::Loader.load, id_sequence: { value: 0 })
    screen = factory.create_unit("unpaid_company", "p")
    archers = factory.create_unit("rooftop_archers", "p")
    roster = [ screen, archers ]
    Sim::Geometry::Deployment.pack_roster!(roster)
    roster.each { |unit| refute_equal "reserve", unit.dig(:components, :formation, :row) }
    distance = Sim::Geometry::Battlefield.distance_between_units(*roster.map { |unit| Sim::Geometry::Deployment.footprint_from_entity(unit) })
    assert_operator distance, :<=, 1.5
    assert_operator archers.dig(:components, :formation, :x), :<, screen.dig(:components, :formation, :x)
    roster.each { |unit| assert_nil Sim::Geometry::Deployment.clash_reason(unit, unit[:components][:formation], roster) }
  end

  private

  class Dice
    attr_reader :calls
    def initialize(values)
      @values = values
      @calls = 0
    end
    def rand(*)
      value = @values[[ @calls, @values.size - 1 ].min]
      @calls += 1
      value
    end
  end

  def dice(*values)
    Dice.new(values)
  end

  def shooter(**overrides)
    unit = BattleScenarios.combatant(ranged: 2, shooting_range: 40, shooting_template: "common", requires_line_of_sight: false, weapon_type: "ranged", missile_attacks: 1, **overrides)
    unit[:contributors][:ranged] = [ unit.except(:contributors).merge(power: unit[:ranged]) ]
    unit
  end

  def side(*units)
    { combatants: units, side_key: units.first[:side_key], player_id: units.first[:side_key] }
  end

  def shot(host, enemies, rng: dice(0.0))
    phase = Attack.create_phase("shooting", "Стрельба")
    actor = Sim::Battle::Decisions::MissileChoice.build_actor(host, host[:contributors][:ranged].first)
    Attack.resolve_missile_strike!(phase: phase, actor: actor, target: enemies.first, vector: "front", attack_type: "shooting", acting_side: side(host), target_side: side(*enemies), round_number: 1, rng: rng)
    phase
  end

  def damage_context(attacker, victim, guard, damage:)
    { phase: Attack.create_phase("melee", "Бой"), attacker: attacker, host: attacker, defender: victim, damage: damage,
      acting_side: side(attacker), target_side: side(victim, guard), attack_type: "melee" }
  end

  def retreat_unit
    BattleScenarios.combatant(abilities: [ "orderlyRetreat" ], current_health: 4, max_health: 4, models_remaining: 4, starting_models: 4, morale: 1)
  end

  def morale_action(unit, enemies)
    Sim::Battle::Phases::Morale.resolve_action(combatant: unit, allies: [ unit ], enemies: enemies, round_number: 1, phase_type: "melee", combat_score_delta: 50, sequence: 0, engaged_enemies: enemies)
  end
end
