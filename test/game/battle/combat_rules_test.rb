require "test_helper"

class SimBattleCombatRulesTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  Attack = Sim::Battle::Phases::AttackResolution
  Movement = Sim::Battle::Phases::Movement
  FearMovement = Sim::Battle::Rules::Fear::Movement
  FearMelee = Sim::Battle::Rules::Fear::Melee
  Melee = Sim::Battle::Phases::Melee
  BreathShooting = Sim::Battle::Rules::Breath::Shooting
  Rules = Sim::Battle::Rules

  test "wildborn rules are registered" do
    assert_includes Sim::Battle::Rules.for(:movement).rules, Sim::Battle::Rules::Wildborn::Movement
    assert_includes Sim::Battle::Rules.for(:morale).rules, Sim::Battle::Rules::Wildborn::Morale
    assert_includes Sim::Battle::Rules.for(:melee).rules, Sim::Battle::Rules::Forestkin::Melee
    assert_includes Sim::Battle::Rules.for(:round).rules, Sim::Battle::Rules::Forestkin::Round
    assert File.exist?(Rails.root.join("app/domain/sim/battle/rules/forestborn/movement.rb"))
  end

  test "rules registry indexes fear under movement and melee" do
    assert_includes Rules.for(:movement).rules, FearMovement
    assert_includes Rules.for(:melee).rules, FearMelee
    assert_includes Rules.for(:melee).rules, Sim::Battle::Rules::Charge::Melee
    assert_includes Rules.for(:shooting).rules, BreathShooting
    assert_includes Rules.for(:shooting).rules, Sim::Battle::Rules::Volley::Shooting
    assert_includes Rules.for(:shooting).rules, Sim::Battle::Rules::Common::Shooting
    assert_includes Rules.for(:shooting).rules, Sim::Battle::Rules::Blast::Shooting
    assert_includes Rules.for(:shooting).rules, Sim::Battle::Rules::AntiFlying::Shooting
    assert_includes Rules.for(:morale).rules, Sim::Battle::Rules::Undead::Morale
    assert_includes Rules.for(:setup).rules, Sim::Battle::Rules::BannerAura::Setup
    assert_includes Rules.for(:round).rules, Sim::Battle::Rules::Undead::Round
    assert_includes Rules.for(:round).rules, Sim::Battle::Rules::LavaSpit::Round
    assert_equal BreathShooting, Rules.for(:shooting).find_applicable({ shooting_template: "breath" }, "shooting")
    assert_equal Sim::Battle::Rules::Volley::Shooting, Rules.for(:shooting).find_applicable({ shooting_template: "volley" }, "shooting")
    assert_equal Sim::Battle::Rules::Common::Shooting, Rules.for(:shooting).find_applicable({ shooting_template: "common" }, "shooting")
    assert_equal Sim::Battle::Rules::Blast::Shooting, Rules.for(:shooting).find_applicable({ shooting_template: "blast" }, "shooting")
    assert_equal Sim::Battle::Rules::Line::Shooting, Rules.for(:shooting).find_applicable({ shooting_template: "line" }, "shooting")
    assert_nil Rules.for(:shooting).find_applicable({ shooting_template: "single" }, "shooting")
  end

  test "rule folders are named by rule with phase files inside" do
    root = Rails.root.join("app/domain/sim/battle/rules")
    assert File.exist?(root.join("fear/movement.rb"))
    assert File.exist?(root.join("fear/melee.rb"))
    assert File.exist?(root.join("fear/morale.rb"))
    assert File.exist?(root.join("breath/shooting.rb"))
    assert File.exist?(root.join("volley/shooting.rb"))
    assert File.exist?(root.join("common/shooting.rb"))
    assert File.exist?(root.join("blast/shooting.rb"))
    assert File.exist?(root.join("charge/melee.rb"))
    assert File.exist?(root.join("flying/movement.rb"))
    assert File.exist?(root.join("ground/movement.rb"))
    assert File.exist?(root.join("undead/morale.rb"))
    assert File.exist?(root.join("undead/round.rb"))
    assert File.exist?(root.join("lava_spit/round.rb"))
    assert File.exist?(root.join("banner_aura/setup.rb"))
  end

  test "skirmisher can shoot outside front arc" do
    shooter = combatant(
      entity_id: "skirm",
      x: 10,
      y: 12,
      facing: 0,
      abilities: [ "skirmisher", "ranged" ],
      ranged: 4,
      targeting_abilities: [ "skirmisher", "ranged" ]
    )
    target = combatant(entity_id: "behind", x: 10, y: 16, facing: 0, side_index: 1)
    all = [ shooter, target ]

    assert Sim::Battle::Decisions::Targeting.can_target_ranged?(shooter, target, all)

    ranked = shooter.merge(abilities: [ "ranged" ], targeting_abilities: [ "ranged" ])
    refute Sim::Battle::Decisions::Targeting.can_target_ranged?(ranked, target, [ ranked, target ])
  end

  test "breath teardrop is 8 inches long from attacker front" do
    attacker = combatant(entity_id: "dragon", x: 10, y: 12, facing: 0, base_width: 2, base_depth: 2, model_width: 2, model_depth: 2, files: 1, ranks: 1, models_remaining: 1)
    target = combatant(entity_id: "victims", x: 16, y: 12, facing: 180, base_width: 4, base_depth: 2, model_width: 1, model_depth: 1, files: 4, ranks: 2, models_remaining: 8, side_index: 1)
    polygon = BF.breath_teardrop_polygon(attacker, target)
    origin = BF.front_center(attacker)
    tip = polygon.first(2)
    tip_mid = { x: (tip[0][:x] + tip[1][:x]) / 2.0, y: (tip[0][:y] + tip[1][:y]) / 2.0 }
    base = polygon.last(2)
    base_mid = { x: (base[0][:x] + base[1][:x]) / 2.0, y: (base[0][:y] + base[1][:y]) / 2.0 }

    assert_in_delta origin[:x], tip_mid[:x], 0.35
    assert_in_delta BF::Templates::BREATH_LENGTH, BF.distance_between(tip_mid, base_mid), 0.2
  end

  test "breath hits models whose center is under the teardrop and logs template details" do
    dragon = combatant(
      entity_id: "dragon",
      name: "Костяной дракон",
      x: 10,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      model_width: 2,
      model_depth: 2,
      files: 1,
      ranks: 1,
      models_remaining: 1,
      model_health: 8,
      current_health: 8,
      max_health: 8,
      ranged: 4,
      melee: 6,
      shooting_template: "breath",
      shooting_range: 8,
      weapon_type: "breath",
      abilities: [ "monster", "flying", "fear", "undead", "ranged" ],
      missile_attacks: 1,
      contributors: { ranged: [ { entity_id: "dragon", name: "Костяной дракон", kind: "unit", ranged: 4, power: 4 } ], melee: [], spell: [] }
    )
    block = combatant(
      entity_id: "block",
      name: "Скелетный блок",
      x: 15,
      y: 12,
      facing: 180,
      base_width: 4,
      base_depth: 2,
      model_width: 1,
      model_depth: 1,
      files: 4,
      ranks: 2,
      models_remaining: 8,
      model_health: 1,
      current_health: 8,
      max_health: 8,
      starting_models: 8,
      melee: 3,
      side_index: 1
    )

    victims = BreathShooting.attack_victims(dragon, block, [ block ])
    assert victims.any?, "expected models under teardrop"
    assert_operator victims.first[:models_hit], :>=, 1

    phase = Attack.create_phase("shooting", "Фаза стрельбы")
    actor = {
      actor_id: "dragon",
      host_id: "dragon",
      actor_name: "Костяной дракон",
      actor_role: "unit",
      contributor: dragon[:contributors][:ranged].first
    }.merge(dragon)

    Attack.resolve_missile_strike!(
      phase: phase,
      actor: actor,
      target: block,
      vector: "front",
      attack_type: "shooting",
      acting_side: { player_id: "p1", combatants: [ dragon ] },
      target_side: { player_id: "p2", combatants: [ block ] },
      round_number: 1,
      rng: Random.new(1)
    )

    action = phase[:actions].find { |row| row[:type] == "shooting" }
    assert action, "expected shooting action"
    assert_equal "polygon", action[:template][:shape]
    assert_equal "breath", action[:template][:kind]
    assert_equal 8.0, action[:template][:length]
    assert action[:models_hit].to_i >= 1
    assert_match(/шаблон|пламя|модел/i, action[:summary])
    assert action[:details].any? { |line| line.include?("template_points=") || line.include?("models_hit=") }
    assert_operator block[:current_health], :<, 8
  end

  test "fear charge check halts before contact when morale fails" do
    charger = charge_combatant(
      entity_id: "orc",
      name: "Orcs",
      x: 12,
      y: 12,
      morale: 8,
      movement: 6
    )
    scary = charge_combatant(
      entity_id: "skel",
      name: "Skels",
      x: 22,
      y: 12,
      facing: 180,
      morale: 7,
      abilities: [ "fear" ],
      side_index: 1
    )
    intent = charge_intent_for(charger, scary)
    refute_nil intent

    check = failing_fear_check(charger, round_number: 1, sequence: 0)
    FearMovement.halt_charge!(intent)
    Movement.apply_intents!([ intent ])
    landed = intent[:combatant]

    refute check[:passed]
    refute Sim::Battle::Decisions::Movement.engaged?(landed, scary)
    assert_operator BF.distance_between_units(landed, scary), :>, Sim::Battle::Decisions::Movement::ENGAGE
    assert_operator BF.distance_between({ x: 12, y: 12 }, landed), :>, 0.05
  end

  test "mutual fear skips charge fear checks" do
    left = charge_combatant(entity_id: "a", x: 12, y: 12, abilities: [ "fear" ], morale: 5)
    right = charge_combatant(entity_id: "b", x: 22, y: 12, facing: 180, abilities: [ "fear" ], morale: 5, side_index: 1)
    phase = Attack.create_phase("movement", "Фаза движения")
    intent = charge_intent_for(left, right)

    FearMovement.prepare_melee_intents!(
      phase: phase,
      intents: [ intent ],
      acting_side: { combatants: [ left ] },
      target_side: { combatants: [ right ] },
      round_number: 1
    )

    assert_empty phase[:actions].select { |row| row[:type] == "fear_check" }
  end

  test "fearless unit ignores enemy fear on charge" do
    fearless = charge_combatant(entity_id: "a", x: 12, y: 12, abilities: [ "fearless" ], movement: 6)
    scary = charge_combatant(entity_id: "b", x: 22, y: 12, facing: 180, abilities: [ "fear" ], side_index: 1)
    phase = Attack.create_phase("movement", "Фаза движения")
    intent = charge_intent_for(fearless, scary)

    FearMovement.prepare_melee_intents!(
      phase: phase,
      intents: [ intent ],
      acting_side: { combatants: [ fearless ] },
      target_side: { combatants: [ scary ] },
      round_number: 1
    )

    assert_empty phase[:actions]
    refute intent.dig(:plan, :fear_halted)
  end

  test "fear check runs once per charger per round across movement waves" do
    normal = charge_combatant(entity_id: "orc", x: 12, y: 12, morale: 5, movement: 6)
    scary = charge_combatant(entity_id: "skel", x: 22, y: 12, facing: 180, abilities: [ "fear" ], side_index: 1)
    intent_a = charge_intent_for(normal, scary)
    intent_b = charge_intent_for(normal, scary)
    phase_a = Attack.create_phase("movement", "Фаза движения")
    phase_b = Attack.create_phase("movement", "Фаза движения")

    FearMovement.prepare_melee_intents!(
      phase: phase_a,
      intents: [ intent_a ],
      acting_side: { combatants: [ normal ] },
      target_side: { combatants: [ scary ] },
      round_number: 2
    )
    FearMovement.prepare_melee_intents!(
      phase: phase_b,
      intents: [ intent_b ],
      acting_side: { combatants: [ normal ] },
      target_side: { combatants: [ scary ] },
      round_number: 2
    )

    fear_actions = (phase_a[:actions] + phase_b[:actions]).select { |row| row[:type] == "fear_check" }
    assert_equal 1, fear_actions.size
    assert_equal "orc", fear_actions.first[:actor_id]
  end

  test "fear charger forces defender check on charge not in melee" do
    scary = charge_combatant(entity_id: "skel", x: 12, y: 12, abilities: [ "fear" ], movement: 6)
    victim = charge_combatant(entity_id: "orc", x: 22, y: 12, facing: 180, side_index: 1, movement: 6)
    intent = charge_intent_for(scary, victim)
    phase = Attack.create_phase("movement", "Фаза движения")

    FearMovement.prepare_melee_intents!(
      phase: phase,
      intents: [ intent ],
      acting_side: { combatants: [ scary ] },
      target_side: { combatants: [ victim ] },
      round_number: 1
    )

    fear_actions = phase[:actions].select { |row| row[:type] == "fear_check" }
    assert_equal 1, fear_actions.size
    assert_equal "orc", fear_actions.first[:actor_id]
  end

  test "already engaged units skip fear checks" do
    scary = combatant(
      entity_id: "skel", x: 12, y: 12, facing: 0, base_width: 2, base_depth: 2, abilities: [ "fear" ], morale: 7,
      contributors: { melee: [ { entity_id: "skel", name: "Skels", kind: "unit", power: 3 } ], ranged: [], spell: [] }
    )
    victim = combatant(
      entity_id: "orc", x: 14.2, y: 12, facing: 180, base_width: 2, base_depth: 2, abilities: [], morale: 5, side_index: 1,
      contributors: { melee: [ { entity_id: "orc", name: "Orcs", kind: "unit", power: 5 } ], ranged: [], spell: [] }
    )
    phase_move = Attack.create_phase("movement", "Фаза движения")
    intent = {
      kind: "approach",
      combatant: victim,
      nearest: scary,
      from: { x: victim[:x], y: victim[:y], facing: victim[:facing] },
      destination: victim.merge(x: victim[:x], y: victim[:y]),
      charge_contact_id: scary[:entity_id],
      wait: false
    }

    FearMovement.prepare_melee_intents!(
      phase: phase_move,
      intents: [ intent ],
      acting_side: { combatants: [ victim ] },
      target_side: { combatants: [ scary ] },
      round_number: 2
    )

    assert_empty phase_move[:actions].select { |row| row[:type] == "fear_check" }
    assert FearMelee.allow_attack?(victim)
  end

  test "movement play logs fear check on charge into scary unit" do
    charger = charge_combatant(entity_id: "orc", x: 12, y: 12, morale: 5, movement: 6)
    scary = charge_combatant(entity_id: "skel", x: 22, y: 12, facing: 180, abilities: [ "fear" ], side_index: 1)

    phase = Movement.play(
      acting_side: { player_id: "p1", side_key: "left", combatants: [ charger ] },
      target_side: { player_id: "p2", side_key: "right", combatants: [ scary ] },
      round_number: 1
    )

    fear_actions = phase[:actions].select { |row| row[:type] == "fear_check" }
    assert_equal 1, fear_actions.size
    assert fear_actions.first[:details].any? { |line| line.include?("fear_check") }
    assert phase[:events].any? { |line| line.match?(/страх|заряд/i) }
  end

  test "support rank doubles front fighters but not beyond remaining models" do
    halberds = combatant(abilities: [ "supportRank" ], files: 4, ranks: 3, models_remaining: 10)
    count = Rules.for(:melee).attacking_model_count(halberds, combatant(side_index: 1), "front", 4)

    assert_equal 8, count
    assert_equal 4, Rules.for(:melee).attacking_model_count(halberds, combatant(side_index: 1), "flank", 4)
  end

  test "support rank needs more than one rank depth" do
    shallow = combatant(abilities: [ "supportRank" ], files: 4, ranks: 1, models_remaining: 4)
    enemy = combatant(side_index: 1)

    assert_equal 4, Rules.for(:melee).attacking_model_count(shallow, enemy, "front", 4)
    assert_empty Rules.for(:melee).log_clauses(
      { host: shallow, attacker: shallow, defender: enemy, attack_type: "melee", vector: "front", contact_side: "front" }
    )
  end

  test "passive log_clauses name rules that actually changed the strike" do
    rules = Rules.for(:melee)
    enemy = combatant(side_index: 1)
    ctx = lambda do |attacker, defender, extra = {}|
      { attacker: attacker, host: attacker, defender: defender, attack_type: "melee", vector: "front" }.merge(extra)
    end

    assert_includes rules.log_clauses(ctx.call(combatant(charged_distance: 5), enemy)), "заряд ×1.3"
    assert_includes rules.log_clauses(ctx.call(combatant(abilities: [ "antiLarge" ]), enemy.merge(model_class: "monster"))), "против крупной цели ×1.35"
    assert_includes rules.log_clauses(ctx.call(combatant(charged_distance: 6), enemy.merge(abilities: [ "shieldwall" ]))), "щитовая стена ×0.75"
    assert_includes rules.log_clauses(ctx.call(combatant(abilities: [ "ferocious" ], ferocious_streak: 2), enemy)), "ярость SK +2"
    assert_includes rules.log_clauses(ctx.call(
      combatant(abilities: [ "supportRank" ], files: 4, models_remaining: 10),
      enemy,
      contact_side: "front"
    )), "второй ряд бьёт"
    assert_empty rules.log_clauses(ctx.call(combatant, enemy))
  end

  test "armor piercing halves armor influence and rune armor reduces non-magic damage" do
    attacker = combatant(abilities: [ "armorPiercing" ])
    defender = combatant(side_index: 1, abilities: [ "runeArmor" ])
    rules = Rules.for(:melee)

    assert_in_delta 1.2, rules.armor_factor(attacker, defender, "melee", 1.4), 0.001
    assert_in_delta 2.0 / 3.0, rules.damage_factor(attacker, defender, "melee", "front", 1), 0.001
    assert_in_delta 1.0, rules.damage_factor(attacker, defender, "magic", "front", 1), 0.001
  end

  test "poison removes one whole living model but not undead" do
    attacker = combatant(abilities: [ "poison" ])
    defender = combatant(side_index: 1, current_health: 7, max_health: 8, model_health: 4, models_remaining: 2)
    phase = Attack.create_phase("melee", "Фаза боя")
    action = {
      damage: 1,
      target_state_before: Sim::Battle::State.snapshot_combatant(defender),
      details: []
    }
    ctx = {
      phase: phase, attacker: attacker, defender: defender, action: action,
      acting_side: { combatants: [ attacker ] }, target_side: { combatants: [ defender ] }
    }

    Sim::Battle::Rules::Poison::Melee.after_hit!(ctx)
    assert_equal 3, defender[:current_health]
    assert_equal 5, action[:damage]

    undead = defender.merge(current_health: 7, abilities: [ "undead" ])
    Sim::Battle::Rules::Poison::Melee.after_hit!(ctx.merge(defender: undead, action: { damage: 1, details: [] }))
    assert_equal 7, undead[:current_health]
  end

  test "poison does not stack when the strike already killed a model" do
    attacker = combatant(abilities: [ "poison" ])
    defender = combatant(side_index: 1, current_health: 10, max_health: 10, model_health: 1, models_remaining: 10)
    before = Sim::Battle::State.snapshot_combatant(defender)
    defender[:current_health] = 9
    Sim::Battle::State.sync_combatant_footprint!(defender)
    action = { damage: 1, target_state_before: before, details: [] }
    ctx = {
      phase: Attack.create_phase("melee", "Фаза боя"),
      attacker: attacker,
      defender: defender,
      action: action,
      acting_side: { combatants: [ attacker ] },
      target_side: { combatants: [ defender ] }
    }

    Sim::Battle::Rules::Poison::Melee.after_hit!(ctx)

    assert_equal 9, defender[:current_health]
    assert_equal 1, action[:damage]
    assert_empty action[:details]
  end

  test "ferocious skill grows once per battle round in continuous contact" do
    orcs = combatant(entity_id: "orcs", x: 10, abilities: [ "ferocious" ], skill: 3)
    enemy = combatant(entity_id: "enemy", x: 10.8, side_index: 1)
    ctx = { acting_side: { combatants: [ orcs ] }, target_side: { combatants: [ enemy ] } }

    Sim::Battle::Rules::Ferocious::Melee.before_play!(ctx.merge(round_number: 1))
    first = Rules.for(:melee).prepare_profile({ skill: 3 }, orcs, enemy, "melee")
    Sim::Battle::Rules::Ferocious::Melee.before_play!(ctx.merge(round_number: 2))
    second = Rules.for(:melee).prepare_profile({ skill: 3 }, orcs, enemy, "melee")

    assert_equal 3, first[:skill]
    assert_equal 4, second[:skill]
  end

  test "boar flank charge grants an extra ferocious skill point" do
    orcs = combatant(entity_id: "orcs", x: 10, y: 12, abilities: [ "ferocious" ], skill: 3)
    boars = combatant(entity_id: "boars", x: 12, y: 14, abilities: [ "boarCharge" ], charged_vector: "flank", charged_target_id: "enemy")
    enemy = combatant(entity_id: "enemy", x: 10.8, y: 12, side_index: 1)
    ctx = { acting_side: { combatants: [ orcs, boars ] }, target_side: { combatants: [ enemy ] }, round_number: 1 }

    Sim::Battle::Rules::Ferocious::Melee.before_play!(ctx)
    Sim::Battle::Rules::Boar::Melee.before_play!(ctx)
    profile = Rules.for(:melee).prepare_profile({ skill: 3 }, orcs, enemy, "melee")

    assert_equal 1, orcs[:ferocious_boar_bonus]
    assert_equal 4, profile[:skill]
  end

  test "shieldwall cuts only a frontal charged strike" do
    attacker = combatant(charged_distance: 6)
    wall = combatant(side_index: 1, abilities: [ "shieldwall" ])
    rules = Rules.for(:melee)

    assert_in_delta 0.975, rules.damage_factor(attacker, wall, "melee", "front", 1), 0.001
    assert_in_delta 1.3, rules.damage_factor(attacker, wall, "melee", "flank", 1), 0.001
    assert_in_delta 1.0, rules.damage_factor(attacker.except(:charged_distance), wall, "melee", "front", 1), 0.001
  end

  test "antiLarge boosts melee against monsters and cavalry only" do
    attacker = combatant(abilities: [ "antiLarge" ])
    rules = Rules.for(:melee)

    assert_in_delta 1.35, rules.damage_factor(attacker, combatant(side_index: 1, model_class: "monster"), "melee", "front", 1), 0.001
    assert_in_delta 1.35, rules.damage_factor(attacker, combatant(side_index: 1, model_class: "cavalry"), "melee", "front", 1), 0.001
    assert_in_delta 1.0, rules.damage_factor(attacker, combatant(side_index: 1, model_class: "infantry"), "melee", "front", 1), 0.001
  end

  test "momentum charge scales with distance and dodge reduces hit chance" do
    rider = combatant(abilities: [ "momentumCharge" ], charged_distance: 8)
    dodger = combatant(side_index: 1, abilities: [ "dodge" ])

    assert_in_delta 1.4, Rules.for(:melee).damage_factor(rider, dodger, "melee", "front", 1), 0.001
    assert_in_delta 0.8, Rules.for(:melee).hit_chance_factor(rider, dodger, "melee"), 0.001
  end

  test "toxin weakens a target once and regen restores a wound" do
    attacker = combatant(abilities: [ "toxin" ])
    defender = combatant(side_index: 1, skill: 4, melee: 5, current_health: 6, max_health: 8)
    phase = Attack.create_phase("melee", "Фаза боя")
    action = { details: [] }
    ctx = {
      phase: phase, attacker: attacker, defender: defender, action: action,
      acting_side: { combatants: [ attacker ] }, target_side: { combatants: [ defender ] }
    }

    Sim::Battle::Rules::Toxin::Melee.after_hit!(ctx)
    Sim::Battle::Rules::Toxin::Melee.after_hit!(ctx.merge(action: { details: [] }))

    assert_equal 3, defender[:skill]
    assert_equal 4, defender[:melee]
    assert defender[:toxin_weakened]
    assert_match(/токсин/, action[:clauses].join)
    assert_empty phase[:events]

    events = Sim::Battle::Rules::Regen::Round.apply_passives!({ combatants: [ defender.merge(abilities: [ "regen" ]) ] })
    assert_match(/регенерац/i, events.first)
  end

  test "ranged attacks stop at shooting range and outriders stay missile movers" do
    shooter = combatant(entity_id: "gun", x: 8, y: 12, facing: 0, ranged: 4, shooting_range: 10, abilities: [ "ranged", "outrider" ])
    near = combatant(entity_id: "near", x: 16, y: 12, side_index: 1)
    close = combatant(entity_id: "close", x: 10, y: 12, side_index: 1)
    far = combatant(entity_id: "far", x: 30, y: 12, side_index: 1)

    assert Sim::Battle::Decisions::Targeting.can_target_ranged?(shooter, near, [ shooter, near ])
    refute Sim::Battle::Decisions::Targeting.can_target_ranged?(shooter, far, [ shooter, far ])
    refute Sim::Battle::Decisions::Movement.melee_movers([ shooter ]).include?(shooter)
    assert_equal :outrider_kite, Rules.for(:movement).reposition_mode(shooter, {
      enemies: [ close ], all: [ shooter, close ], terrain: []
    })
  end

  test "throw rocks and forestborn use movement hooks instead of melee approach" do
    treeman = combatant(entity_id: "tree", melee: 6, ranged: 2, abilities: [ "throwRocks", "ranged" ], shooting_range: 8)
    archer = combatant(entity_id: "arch", melee: 2, ranged: 5, abilities: [ "forestborn", "ranged" ], shooting_range: 11)
    forest = [ { id: "f1", type: "forest", x: 12, y: 12, width: 4, depth: 3, impassable: false, blocks_los: false } ]

    refute Sim::Battle::Decisions::Movement.melee_movers([ treeman ]).include?(treeman)
    assert_equal :forest_seek, Rules.for(:movement).reposition_mode(archer, {
      enemies: [ combatant(entity_id: "e", x: 18, side_index: 1) ],
      all: [ archer ],
      terrain: forest
    })
  end

  test "line template counts each crossed model" do
    cannon = combatant(x: 5, y: 12, facing: 0, shooting_range: 20, shooting_template: "line")
    block = combatant(
      x: 12, y: 12, facing: 180, side_index: 1,
      files: 1, ranks: 3, models_remaining: 3,
      base_width: 1, base_depth: 3
    )
    victims = Sim::Battle::Rules::Line::Shooting.attack_victims(cannon, block, [ block ])

    assert_equal 3, victims.first[:models_hit]
  end

  test "sling catapult gains blast only with sling fodder within six inches" do
    diver = combatant(entity_id: "diver", x: 10, abilities: [ "slingCatapult", "machine" ], shooting_template: "single")
    goblins = combatant(entity_id: "goblins", x: 14, abilities: [ "slingFodder" ])
    enemy = combatant(entity_id: "enemy", x: 20, side_index: 1)
    ctx = {
      phase: Attack.create_phase("shooting", "Фаза стрельбы"),
      acting_side: { combatants: [ diver, goblins ] },
      target_side: { combatants: [ enemy ] }
    }

    Sim::Battle::Rules::SlingCatapult::Shooting.before_play!(ctx)

    assert_equal "goblins", diver[:sling_catapult_fodder_id]
    assert Sim::Battle::Rules::SlingCatapult::Shooting.applies?(diver, "shooting")
    assert_equal Sim::Battle::Rules::SlingCatapult::Shooting, Rules.for(:shooting).find_applicable(diver, "shooting")
  end

  test "corpse trail hit summons raised dead facing nearest enemy" do
    cart = combatant(entity_id: "cart", abilities: [ "corpseTrail" ])
    target = combatant(entity_id: "target", x: 15, y: 12, side_index: 1)
    far_enemy = combatant(entity_id: "far", x: 24, y: 12, side_index: 1)
    acting_side = { side_key: "left", combatants: [ cart ] }
    target_side = { side_key: "right", combatants: [ target, far_enemy ] }
    action = { details: [] }
    phase = Attack.create_phase("shooting", "Фаза стрельбы")

    Sim::Battle::Rules::CorpseTrail::Shooting.after_hit!(
      phase: phase,
      host: cart,
      defender: target,
      action: action,
      terrain: [],
      acting_side: acting_side,
      target_side: target_side
    )

    summoned = acting_side[:combatants].find { |entry| entry[:summoned] }
    assert summoned
    assert_equal "zombies", summoned[:summon_kind]
    assert_equal "Поднятые мертвецы", summoned[:name]
    assert_includes action[:summon_ids], summoned[:entity_id]
    nearest_heading = BF.heading_to(summoned, target)
    assert_in_delta nearest_heading, summoned[:facing], 1.0
  end

  test "wildborn charges forest-hidden enemies from outside the woods" do
    woods = { id: "forest-a", type: "forest", x: 20, y: 12, width: 5, depth: 5, impassable: false, blocks_los: false }
    attacker = charge_combatant(entity_id: "wild", x: 12, y: 12, abilities: [ "wildborn" ])
    defender = charge_combatant(entity_id: "in", x: 20, y: 12, side_index: 1)
    plain = charge_combatant(entity_id: "plain", x: 12, y: 12)

    refute Sim::Battle::Decisions::Movement.can_charge?(plain, defender, [ woods ])
    assert Sim::Battle::Decisions::Movement.can_charge?(attacker, defender, [ woods ])
  end

  test "wildborn in forest ignores enemy fear on charge" do
    woods = { id: "forest-a", type: "forest", x: 12, y: 12, width: 5, depth: 5, impassable: false, blocks_los: false }
    wildborn = charge_combatant(entity_id: "wild", x: 12, y: 12, abilities: [ "wildborn" ])
    scary = charge_combatant(entity_id: "scary", x: 18, y: 12, side_index: 1, abilities: [ "fear" ])
    intent = charge_intent_for(wildborn, scary)

    FearMovement.prepare_melee_intents!(
      phase: Attack.create_phase("movement", "Фаза движения"),
      intents: [ intent ],
      acting_side: { combatants: [ wildborn ] },
      target_side: { combatants: [ scary ] },
      round_number: 1,
      terrain: [ woods ]
    )

    refute intent[:plan][:fear_halted]
  end

  test "forestkin melee hit plants forest and regrows in woods" do
    dryad = combatant(entity_id: "dryad", abilities: [ "forestkin" ], melee: 4)
    target = combatant(entity_id: "target", x: 18, y: 12, side_index: 1)
    terrain = []
    action = { details: [] }
    acting_side = { combatants: [ dryad ] }
    target_side = { combatants: [ target ] }

    Sim::Battle::Rules::Forestkin::Melee.after_hit!(
      phase: Attack.create_phase("melee", "Фаза боя"),
      host: dryad,
      defender: target,
      action: action,
      acting_side: acting_side,
      target_side: target_side,
      attack_type: "melee",
      terrain: terrain
    )

    assert_equal 1, terrain.length
    assert_equal "forest", terrain.first[:type]
    assert_match(/лес прорастает/, action[:clauses].join)
    assert_equal "add", action[:terrain_delta].first[:operation]
    assert_equal "forest", action[:terrain_delta].first[:feature][:type]

    wounded = dryad.merge(current_health: 5, max_health: 8, x: 18, y: 12)
    events = Sim::Battle::Rules::Forestkin::Round.apply_passives!(
      { combatants: [ wounded ], terrain: terrain }
    )
    assert_equal 6, wounded[:current_health]
    assert_match(/регенерац/i, events.first)
  end

  test "seeds wire breath shooting on bone dragon" do
    source = File.read(Rails.root.join("db/seeds.rb"))
    assert_match(/bone_dragon/, source)
    assert_match(/weapon_type:\s*"breath"/, source)
    assert_match(/return "breath" if attributes\.fetch\(:weapon_type\) == "breath"/, source)
  end

  test "undead faction regen requires living general" do
    skeleton = combatant(name: "Skeleton", abilities: [ "undead" ], current_health: 10, max_health: 22)
    side = {
      faction_id: "undead",
      player_name: "Necromancer",
      combatants: [ skeleton ],
      rng: Random.new(1)
    }

    assert_empty Sim::Battle::Rules::Undead::Round.apply_passives!(side)

    general = combatant(entity_id: "gen", kind: "hero", is_general: true, current_health: 3)
    events = Sim::Battle::Rules::Undead::Round.apply_passives!(side.merge(combatants: [ skeleton, general ]))
    assert_equal 1, events.length
    assert_equal 11, skeleton[:current_health]
  end

  test "undead faction regen ignores non-undead wounded units" do
    ghoul = combatant(name: "Ghoul", abilities: [ "fear", "poison" ], current_health: 10, max_health: 12)
    skeleton = combatant(name: "Skeleton", abilities: [ "undead" ], current_health: 10, max_health: 22)
    general = combatant(entity_id: "gen", is_general: true, current_health: 3)
    side = {
      faction_id: "undead",
      player_name: "Necromancer",
      combatants: [ ghoul, skeleton, general ],
      rng: Random.new(1)
    }

    events = Sim::Battle::Rules::Undead::Round.apply_passives!(side)
    assert_equal 1, events.length
    assert_equal 11, skeleton[:current_health]
    assert_equal 10, ghoul[:current_health]
  end

  test "lava spit ignores armor and shieldwall on hit" do
    LavaSpit = Sim::Battle::Rules::LavaSpit::Round
    troll = combatant(
      entity_id: "troll",
      x: 0,
      y: 0,
      facing: 0,
      base_width: 3,
      base_depth: 1,
      abilities: [ "lavaSpit" ],
      melee: 6,
      skill: 6,
      models_remaining: 1,
      model_health: 5,
      current_health: 5,
      max_health: 15
    )
    defender = combatant(
      entity_id: "wall",
      side_index: 1,
      x: 1,
      y: 0,
      facing: 180,
      base_width: 4,
      base_depth: 1,
      armor_type: "heavy",
      abilities: [ "shieldwall" ],
      current_health: 20,
      max_health: 20,
      model_health: 1,
      models_remaining: 20
    )
    side = {
      combatants: [ troll ],
      enemy_side: { combatants: [ defender ] },
      rng: Random.new(0)
    }

    events = LavaSpit.apply_passives!(side)
    assert_equal 1, events.length, events.inspect
    assert_operator defender[:current_health], :<, 20
    assert_includes events.first, "лавовый харчок"
    assert_equal 3, LavaSpit.send(:defenseless_damage, troll)
    assert_equal 2, Attack.damage(troll, defender, "melee", "front", 1)
  end

  test "lava spit uses flat damage without facing bonuses" do
    troll = combatant(melee: 6, abilities: [ "lavaSpit" ])
    plain = combatant(side_index: 1, armor_type: "medium")
    flat = Sim::Battle::Rules::LavaSpit::Round.send(:defenseless_damage, troll)

    assert_equal 3, flat
    assert_equal 5, Attack.damage(troll, plain, "melee", "rear", 1)
    assert_operator flat, :<, Attack.damage(troll, plain, "melee", "rear", 1)
  end

  test "ghoul pack keeps undead faction tier without undead ability" do
    source = File.read(Rails.root.join("db/seeds.rb"))
    ghoul_line = source[/template_key: "ghoul_pack"[^\n]+/]
    assert ghoul_line
    assert_includes ghoul_line, 'faction_slug: "undead"'
    assert_match(/abilities: \[ "fear", "skirmisher", "poison" \]/, ghoul_line)
  end

  test "poison skips extra model kill on 1W targets but kills a whole model on multi-wound" do
    Poison = Sim::Battle::Rules::Poison::Melee
    handgunner = combatant(name: "Аркебузиры", model_health: 1, current_health: 10, models_remaining: 10, abilities: [])
    ghoul = combatant(name: "Упырь", model_health: 1, current_health: 12, models_remaining: 12, abilities: [ "poison" ])
    troll = combatant(name: "Troll", model_health: 5, current_health: 15, models_remaining: 3, model_class: "monster", abilities: [])

    before = Sim::Battle::State.snapshot_combatant(handgunner)
    action = {
      poison_model_applied: false,
      target_state_before: before,
      damage: 1
    }
    Poison.after_hit!(
      attacker: ghoul, host: ghoul, defender: handgunner, action: action,
      acting_side: { combatants: [ ghoul ] }, target_side: { combatants: [ handgunner ] },
      round_number: 1, attack_type: "melee"
    )
    assert_equal 10, handgunner[:current_health]

    troll_before = Sim::Battle::State.snapshot_combatant(troll)
    troll_action = { poison_model_applied: false, target_state_before: troll_before, damage: 2 }
    Poison.after_hit!(
      attacker: ghoul, host: ghoul, defender: troll, action: troll_action,
      acting_side: { combatants: [ ghoul ] }, target_side: { combatants: [ troll ] },
      round_number: 1, attack_type: "melee"
    )
    assert_equal 10, troll[:current_health]
    assert troll_action[:poison_model_applied]
  end

  test "anti flying halves machine shooting damage against flyers" do
    AntiFlying = Sim::Battle::Rules::AntiFlying::Shooting
    Machine = Sim::Battle::Rules::Machine::Shooting
    cannon = combatant(abilities: [ "machine", "antiFlying" ])
    flyer = combatant(abilities: [ "flying" ])
    ground = combatant(abilities: [])

    machine = Machine.damage_factor(cannon, ground, "shooting", "front", 1)
    vs_flyer = Rules.for(:shooting).damage_factor(cannon, flyer, "shooting", "front", 1)
    vs_ground = Rules.for(:shooting).damage_factor(cannon, ground, "shooting", "front", 1)

    assert_in_delta 1.25, machine, 0.001
    assert_in_delta 0.625, vs_flyer, 0.001
    assert_in_delta 1.25, vs_ground, 0.001
    assert_equal 0.5, AntiFlying.damage_factor(cannon, flyer, "shooting", "front", 1)
  end

  test "heavy blast expands blast template radius" do
    Blast = Sim::Battle::Rules::Blast::Shooting
    base = Sim::Geometry::Battlefield::CONFIG[:blast_radius]

    assert_in_delta base, Blast.send(:blast_radius, combatant(abilities: [])), 0.001
    assert_in_delta base * 1.5, Blast.send(:blast_radius, combatant(abilities: [ "heavyBlast" ])), 0.001
  end

  test "melee miss is persisted as a phase action" do
    attacker = combatant(
      entity_id: "riders",
      name: "Наездники",
      x: 10,
      y: 12,
      facing: 0,
      base_width: 3,
      base_depth: 4,
      files: 3,
      ranks: 2,
      melee: 6,
      skill: 4,
      attacks: 1,
      contributors: {
        melee: [ { entity_id: "riders", name: "Наездники", kind: "unit", power: 6 } ],
        ranged: [],
        spell: []
      }
    )
    defender = combatant(
      entity_id: "warden",
      name: "Страж",
      x: 12,
      y: 12,
      facing: 180,
      kind: "hero",
      base_width: 1,
      base_depth: 1,
      files: 1,
      ranks: 1,
      melee: 5,
      skill: 5,
      attacks: 2,
      contributors: {
        melee: [ { entity_id: "warden", name: "Страж", kind: "hero", power: 5 } ],
        ranged: [],
        spell: []
      }
    )
    acting_side = { combatants: [ attacker ] }
    target_side = { combatants: [ defender ] }
    phase = Attack.create_phase("melee", "melee")
    selection = Sim::Battle::Decisions::Targeting.choose_target(attacker, [ defender ], "melee", [ attacker, defender ])
    assert selection

    Attack.resolve_melee_strike!(
      phase: phase,
      attacker: attacker,
      target: defender,
      vector: selection[:vector],
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1,
      rng: always_miss_rng,
      terrain: []
    )

    assert phase[:events].any? { |event| event.include?("0 из") }
    miss = phase[:actions].find { |action| action[:damage].to_i.zero? }
    assert miss, "expected miss action in phase log"
    assert_equal "riders", miss[:actor_id]
    assert_equal "warden", miss[:target_id]
    assert_equal 0, miss[:hits_landed]
    assert miss[:attacks_attempted].to_i.positive?
    assert_match(/0 из \d+ атак/, miss[:summary])
  end

  private

  def charge_combatant(**overrides)
    combatant(
      facing: 0,
      base_width: 2,
      base_depth: 2,
      movement: 6,
      melee: 5,
      morale: 6,
      contributors: {
        melee: [ { entity_id: overrides[:entity_id] || "unit-1", name: overrides[:name] || "Unit", kind: "unit", power: 5 } ],
        ranged: [],
        spell: []
      },
      **overrides
    )
  end

  def charge_intent_for(charger, scary)
    intent = Sim::Battle::Decisions::Movement.build_approach_intent(
      combatant: charger,
      nearest: scary,
      obstacles: [ scary ],
      enemies: [ scary ],
      chargeable: true
    )
    return nil unless intent

    intent.merge(
      from: { x: charger[:x], y: charger[:y], facing: charger[:facing], row: charger[:row], lane: charger[:lane] },
      before: Sim::Battle::State.snapshot_combatant(charger),
      origin_pose: charger.dup
    )
  end

  def failing_fear_check(combatant, round_number:, sequence: 0)
    20.times do |seq|
      check = Sim::Battle::Phases::Morale.resolve_check(
        combatant: combatant,
        allies: [ combatant ],
        enemies: [ { abilities: [ "fear" ], x: combatant[:x], y: combatant[:y] } ],
        round_number: round_number,
        phase_type: "fear",
        combat_score_delta: 0,
        sequence: seq
      )
      return check unless check[:passed]
    end
    flunk "expected a failing fear roll within 20 sequences"
  end

  def always_miss_rng
  Object.new.tap do |rng|
    rng.define_singleton_method(:rand) { |_max = nil| 1.0 }
  end
end

  def combatant(**overrides)
    {
      entity_id: "unit-1",
      name: "Unit",
      kind: "unit",
      side_index: 0,
      side_key: overrides[:side_index].to_i == 1 ? "right" : "left",
      lane: "center",
      row: "front",
      x: 0,
      y: 0,
      facing: 0,
      base_width: 2,
      base_depth: 1,
      model_width: 1,
      model_depth: 1,
      frontage: 2,
      max_files: 5,
      files: 2,
      ranks: 1,
      current_health: 8,
      max_health: 8,
      model_health: 1,
      models_remaining: 8,
      starting_models: 8,
      is_routing: false,
      initiative: 3,
      skill: 3,
      morale: 6,
      melee: 4,
      ranged: 0,
      spell: 0,
      armor_type: "medium",
      weapon_type: "slash",
      movement: 3,
      abilities: [],
      attacks: 2,
      missile_attacks: 1,
      shooting_template: "single",
      spell_template: "single",
      requires_line_of_sight: true,
      contributors: { melee: [], ranged: [], spell: [] },
      attached_heroes: []
    }.merge(overrides)
  end
end
