require "test_helper"

class SimBattleNeutralCountersTest < ActiveSupport::TestCase
  Rules = Sim::Battle::Rules
  Attack = Sim::Battle::Phases::AttackResolution
  Sky = Rules::SkySnare::Movement
  Battery = Rules::CounterBattery::Shooting
  Barricade = Rules::ChargeBarricade::Melee
  Banish = Rules::BanishSummons::Round

  test "counter rules and automatic deployment contracts are registered" do
    assert_includes Rules.for(:movement).rules, Sky
    assert_includes Rules.for(:movement).rules, Rules::ChargeBarricade::Movement
    assert_includes Rules.for(:melee).rules, Barricade
    assert_includes Rules.for(:round).rules, Banish
    assert_equal Battery, Rules.for(:shooting).find_applicable({ abilities: [ "counterBattery" ], shooting_template: "common" }, "shooting")
    assert_includes Rules.army_synergies, Sky::SYNERGY
    assert_equal :artillery, Sim::ArmyComposition.bot_pack_as(abilities: [ "counterBattery" ])
    assert_equal :frontline, Sim::ArmyComposition.bot_pack_as(abilities: [ "chargeBarricade" ])
    assert Sky::SYNERGY.benefits?({ ranged: 4 }, { abilities: [ "skySnare" ] })
    assert_equal [ 6.0, true ], Sky::SYNERGY.placement({ ranged: 4 }, { abilities: [ "skySnare" ] })
    assert_equal 0, Sky::SYNERGY.capacity_for(abilities: [ "skySnare" ], models: 0)
  end

  test "flight is intercepted before landing contact and cannot deliver its charge" do
    flyer = combatant(x: 6, movement: 10, abilities: [ "flying", "momentumCharge" ])
    guard = enemy(x: 19, abilities: [ "skySnare" ], movement: 0)
    phase = Sim::Battle::Phases::Movement.play(
      acting_side: side(flyer), target_side: side(guard), round_number: 1
    )

    assert_equal 1, guard[:sky_snare_shots]
    refute Sim::Geometry::Battlefield.melee_contact?(flyer, guard)
    assert_nil flyer[:charged_distance]
    assert_operator flyer[:x], :<=, 13.01
    assert_rule_log phase, "sky_snare"
    assert_nil Sim::Battle::Decisions::Targeting.choose_target(flyer, [ guard ], "melee", [ flyer, guard ])
  end

  test "sky snare has two uses and ground movement does not spend them" do
    flyer = combatant(abilities: [ "flying" ])
    guard = enemy(x: 18, abilities: [ "skySnare" ])
    ctx = flight_context(flyer, guard)
    2.times do
      ctx[:intents] = [ flight_intent(flyer) ]
      Sky.prepare_movement_intents!(ctx)
      assert_nil ctx[:intents].first[:charge_contact_id]
    end
    ctx[:intents] = [ flight_intent(flyer) ]
    Sky.prepare_movement_intents!(ctx)
    assert_equal "enemy-1", ctx[:intents].first[:charge_contact_id]
    assert_equal 2, guard[:sky_snare_shots]

    guard.delete(:sky_snare_shots)
    flyer[:abilities] = []
    Sky.prepare_movement_intents!(ctx)
    assert_nil guard[:sky_snare_shots]
  end

  test "intercepted landing backs away from impassable terrain and other trays" do
    flyer = combatant(abilities: [ "flying" ])
    guard = enemy(x: 18, abilities: [ "skySnare" ])
    terrain = BattleScenarios.terrain(x: 12, y: 12, width: 3, depth: 5)
    ctx = flight_context(flyer, guard).merge(terrain: [ terrain ])
    Sky.prepare_movement_intents!(ctx)
    landing = flyer.merge(ctx[:intents].first[:destination])

    assert_equal 1, guard[:sky_snare_shots]
    assert_operator landing[:x], :<, 10
    assert_nil Sim::Battle::Pathing.first_blocker(
      landing, Sim::Battle::Pathing::Obstacles.merge([ guard ], [ terrain ]), origin: landing
    )
  end

  test "sky snare cannot intercept a path outside its protected zone or while routing" do
    flyer = combatant(abilities: [ "flying" ])
    guard = enemy(x: 18, y: 22, abilities: [ "skySnare" ])
    ctx = flight_context(flyer, guard)
    Sky.prepare_movement_intents!(ctx)
    assert_nil guard[:sky_snare_shots]
    guard[:y] = 12
    guard[:is_routing] = true
    Sky.prepare_movement_intents!(ctx)
    assert_nil guard[:sky_snare_shots]
  end

  test "counter battery waits for actual firing and prioritizes a fired machine over infantry" do
    host = shooter(abilities: [ "counterBattery" ])
    machine = enemy(x: 18, abilities: [ "machine" ], has_fired: true)
    infantry = enemy(entity_id: "infantry", x: 13, y: 18, lane: "center")
    actor = actor_for(host)
    selection = Sim::Battle::Decisions::Targeting.choose_target(actor, [ infantry, machine ], "shooting", [ host, machine, infantry ])
    assert_equal machine, selection[:target]
    assert Battery.special_shot?(actor, machine)
    machine.delete(:has_fired)
    refute Battery.special_shot?(actor, machine)
    machine[:has_fired] = true
    actor[:counter_battery_shots] = 2
    refute Battery.special_shot?(actor, machine)
  end

  test "successful counter battery shot deals six damage and prevents exactly the next own shooting phase" do
    host = shooter(abilities: [ "counterBattery" ])
    machine = shooter(enemy: true, x: 18, abilities: [ "machine" ], has_fired: true, current_health: 20, max_health: 20)
    phase = shoot(host, machine)
    assert_equal 14, machine[:current_health]
    assert_equal 1, host[:counter_battery_shots]
    assert machine[:counter_battery_jammed]
    assert host[:has_fired]
    assert_match(/контрбатарейный/, phase[:actions].find { |action| action[:type] == "shooting" }[:summary])
    assert_empty Sim::Battle::Phases::Missile.plan(acting_side: side(machine), target_side: side(host), round_number: 1)

    before = host[:current_health]
    Sim::Battle::Phases::Shooting.play(acting_side: side(machine), target_side: side(host), round_number: 1, rng: always_hit)
    assert_equal before, host[:current_health]
    refute machine[:counter_battery_jammed]
    assert Sim::Battle::Phases::Missile.plan(acting_side: side(machine), target_side: side(host), round_number: 2).any?
  end

  test "counter battery miss spends ammunition and records machine firing but does not jam" do
    host = shooter(abilities: [ "counterBattery", "machine" ])
    target = enemy(x: 18, abilities: [ "machine" ], has_fired: true)
    phase = shoot(host, target, rng: always_miss)
    assert_equal 1, host[:counter_battery_shots]
    assert host[:has_fired]
    refute target[:counter_battery_jammed]
    assert_equal 0, phase[:actions].first[:hits_landed]
    assert_equal 1, phase[:actions].first[:attacks_attempted]
  end

  test "warmup or supply actions do not reveal an unfired machine" do
    host = shooter(abilities: [ "machine" ])
    Battery.after_attack!(host: host, attack_type: "shooting", actions: [ { type: "sling_catapult_ammo", damage: 1 } ])
    refute host[:has_fired]
    Battery.after_attack!(host: host, attack_type: "shooting", actions: [ { type: "shooting", target_state_before: { current_health: 8 } } ])
    assert host[:has_fired], "template fire without attack roll count must also reveal the machine"
  end

  test "counter battery expected damage matches the single special shot and ordinary fallback" do
    host = shooter(abilities: [ "counterBattery" ], skill: 7)
    target = enemy(abilities: [ "machine" ], has_fired: true, current_health: 12)
    actor = actor_for(host)
    assert_equal 6, Battery.expected_damage(actor, target, "front", 1, "shooting", [ target ])
    target[:has_fired] = false
    assert_equal Rules::Common::Shooting.expected_damage(actor, target, "front", 1, "shooting", [ target ]),
      Battery.expected_damage(actor, target, "front", 1, "shooting", [ target ])
  end

  test "banishment affects only nearby enemy summons and logs actual capped damage" do
    source = combatant(abilities: [ "banishSummons" ])
    ally = combatant(entity_id: "ally", summoned: true)
    summoned = enemy(x: 10, summoned: true, current_health: 3)
    ordinary = enemy(entity_id: "ordinary", x: 10, abilities: [ "undead" ])
    distant = enemy(entity_id: "distant", x: 30, summoned: true)
    phase = Attack.create_phase("start", "Конец раунда")
    Banish.after_play!(phase: phase, sides: [ side(source, ally), side(summoned, ordinary, distant) ])

    assert_equal 0, summoned[:current_health]
    [ ally, ordinary, distant ].each { |unit| assert_equal 8, unit[:current_health] }
    assert_equal 3, phase[:actions].first[:damage]
    assert_rule_log phase, "banish_summons"
  end

  test "round orchestrator invokes banishment after both turns and records a valid replay phase" do
    source = combatant(abilities: [ "banishSummons" ], movement: 0, melee: 0)
    target = enemy(x: 10, summoned: true, movement: 0, melee: 0)
    battle = { sides: { left: side(source), right: side(target) }, terrain: [] }
    result = Sim::Battle::Round.play(battle: battle, round_number: 1, rng: Sim::Rng::Seeded.new(42))

    assert_equal 4, target[:current_health]
    assert_equal 2, result[:turns].size
    end_phase = result[:turns].last[:phases].last
    assert_equal "start", end_phase[:type]
    assert_equal "Конец раунда", end_phase[:label]
    assert_rule_log end_phase, "banish_summons"
  end

  test "long frontal charge is countered before melee strikes with capped retaliation" do
    defender = enemy(x: 10, abilities: [ "chargeBarricade" ])
    charger = combatant(x: 8.0, abilities: [ "momentumCharge" ], charged_distance: 8, charged_target_id: defender[:entity_id])
    charger.merge!(Sim::Geometry::Battlefield.charge_destination(charger, defender))
    assert Sim::Geometry::Battlefield.melee_contact?(charger, defender)
    phase = Attack.create_phase("melee", "Бой")
    Barricade.before_play!(phase: phase, acting_side: side(charger), target_side: side(defender))
    assert_equal 4, charger[:current_health]
    assert_equal 0, charger[:charged_distance]
    assert_equal 1, Rules::MomentumCharge::Melee.damage_factor(charger, defender, "melee", "front", 1)
    assert_rule_log phase, "charge_barricade"
    Barricade.before_play!(phase: phase, acting_side: side(charger), target_side: side(defender))
    assert_equal 1, phase[:actions].size
  end

  test "short charges flank charges moving defenders and ordinary melee bypass barricades" do
    defender = enemy(x: 10, abilities: [ "chargeBarricade" ])
    charger = combatant(x: 7.8, charged_distance: 8, charged_target_id: defender[:entity_id])
    [
      [ charger.merge(charged_distance: 2), defender ],
      [ charger.merge(x: 10, y: 9.8), defender ],
      [ charger, defender.merge(barricade_braced: false) ],
      [ charger.merge(charged_distance: nil), defender ]
    ].each do |attacker, guard|
      refute Barricade.protected?(attacker, guard)
      assert_equal attacker, Barricade.prepare_profile(attacker, attacker, guard, "melee")
    end
  end

  test "barricades hold for imminent cavalry but advance against other troops" do
    guard = combatant(abilities: [ "chargeBarricade" ])
    cavalry = enemy(x: 15, movement: 6, abilities: [ "momentumCharge" ])
    infantry = enemy(x: 15, movement: 4)
    rule = Rules::ChargeBarricade::Movement
    assert_equal 0, rule.movement_multiplier(guard, enemies: [ cavalry ])
    assert_equal 1, rule.movement_multiplier(guard, enemies: [ infantry ])
    assert_equal 1, rule.movement_multiplier(guard, enemies: [ cavalry.merge(x: 35) ])
    phase = Sim::Battle::Phases::Movement.play(acting_side: side(guard), target_side: side(cavalry), round_number: 1)
    assert guard[:barricade_braced]
    assert_in_delta 6, guard[:x], 0.01
    assert_empty phase[:actions].select { |action| action[:type] == "movement" }
  end

  private

  def combatant(**attrs)
    BattleScenarios.combatant(**attrs)
  end

  def enemy(**attrs)
    BattleScenarios.enemy(**attrs)
  end

  def side(*units)
    { combatants: units, player_id: units.first[:side_key], player_name: units.first[:side_key], side_key: units.first[:side_key] }
  end

  def shooter(enemy: false, **attrs)
    host = enemy ? self.enemy(**attrs) : combatant(**attrs)
    host.merge!(ranged: 2, shooting_range: 40, shooting_template: "common", requires_line_of_sight: false, weapon_type: "ranged", missile_attacks: 1)
    host[:contributors][:ranged] = [ host.except(:contributors).merge(power: host[:ranged]) ]
    host
  end

  def actor_for(host)
    Sim::Battle::Decisions::MissileChoice.build_actor(host, host[:contributors][:ranged].first)
  end

  def shoot(host, target, rng: always_hit)
    phase = Attack.create_phase("shooting", "Стрельба")
    Attack.resolve_missile_strike!(phase: phase, actor: actor_for(host), target: target, vector: "front",
      attack_type: "shooting", acting_side: side(host), target_side: side(target), round_number: 1, rng: rng)
    phase
  end

  def always_hit
    Struct.new(:value) { def rand(*) = value }.new(0.0)
  end

  def always_miss
    Struct.new(:value) { def rand(*) = value }.new(0.999)
  end

  def flight_intent(flyer)
    destination = flyer.merge(x: 20)
    { combatant: flyer, from: flyer.slice(:x, :y, :facing), destination: destination,
      charge_contact_id: "enemy-1", plan: { leap: true, charge: true } }
  end

  def flight_context(flyer, guard)
    { phase: Attack.create_phase("movement", "Движение"), intents: [ flight_intent(flyer) ],
      acting_side: side(flyer), target_side: side(guard), terrain: [] }
  end

  def assert_rule_log(phase, type)
    action = phase[:actions].find { |entry| entry[:type] == type }
    assert action, "expected #{type} action"
    assert action[:summary].present?
    assert action[:details].any?
    assert_includes phase[:events], action[:summary]
  end
end
