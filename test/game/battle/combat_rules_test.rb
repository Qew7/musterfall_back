require "test_helper"

class SimBattleCombatRulesTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  Attack = Sim::Battle::Phases::AttackResolution
  Melee = Sim::Battle::Phases::Melee
  FearMelee = Sim::Battle::Rules::Fear::Melee
  BreathShooting = Sim::Battle::Rules::Breath::Shooting
  Rules = Sim::Battle::Rules

  test "rules registry indexes fear under melee and breath under shooting" do
    assert_includes Rules.for(:melee).rules, FearMelee
    assert_includes Rules.for(:melee).rules, Sim::Battle::Rules::Charge::Melee
    assert_includes Rules.for(:shooting).rules, BreathShooting
    assert_includes Rules.for(:shooting).rules, Sim::Battle::Rules::Volley::Shooting
    assert_includes Rules.for(:shooting).rules, Sim::Battle::Rules::Blast::Shooting
    assert_includes Rules.for(:morale).rules, Sim::Battle::Rules::Undead::Morale
    assert_includes Rules.for(:setup).rules, Sim::Battle::Rules::BannerAura::Setup
    assert_includes Rules.for(:round).rules, Sim::Battle::Rules::Undead::Round
    assert_equal BreathShooting, Rules.for(:shooting).find_applicable({ shooting_template: "breath" }, "shooting")
    assert_equal Sim::Battle::Rules::Volley::Shooting, Rules.for(:shooting).find_applicable({ shooting_template: "volley" }, "shooting")
    assert_equal Sim::Battle::Rules::Blast::Shooting, Rules.for(:shooting).find_applicable({ shooting_template: "blast" }, "shooting")
    assert_nil Rules.for(:shooting).find_applicable({ shooting_template: "single" }, "shooting")
  end

  test "rule folders are named by rule with phase files inside" do
    root = Rails.root.join("app/domain/sim/battle/rules")
    assert File.exist?(root.join("fear/melee.rb"))
    assert File.exist?(root.join("fear/morale.rb"))
    assert File.exist?(root.join("breath/shooting.rb"))
    assert File.exist?(root.join("volley/shooting.rb"))
    assert File.exist?(root.join("blast/shooting.rb"))
    assert File.exist?(root.join("charge/melee.rb"))
    assert File.exist?(root.join("flying/movement.rb"))
    assert File.exist?(root.join("ground/movement.rb"))
    assert File.exist?(root.join("undead/morale.rb"))
    assert File.exist?(root.join("undead/round.rb"))
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

  test "breath hits models covered more than half and logs template details" do
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

  test "fear from attacker suppresses defender melee when morale fails" do
    scary = combatant(
      entity_id: "scary",
      name: "Отродье",
      x: 12,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      melee: 5,
      morale: 7,
      abilities: [ "fear", "monster" ],
      skill: 4,
      attacks: 2,
      contributors: { melee: [ { entity_id: "scary", name: "Отродье", kind: "unit", power: 5 } ], ranged: [], spell: [] }
    )
    victim = combatant(
      entity_id: "victim",
      name: "Мародеры",
      x: 14.2,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      morale: 2,
      abilities: [],
      skill: 3,
      attacks: 1,
      side_index: 1,
      contributors: { melee: [ { entity_id: "victim", name: "Мародеры", kind: "unit", power: 4 } ], ranged: [], spell: [] }
    )

    assert_operator BF.distance_between_units(scary, victim), :<=, Attack::CONTACT + BF::CONFIG[:contact_snap]

    phase = Melee.play(
      acting_side: { player_id: "p1", side_key: "left", combatants: [ scary ] },
      target_side: { player_id: "p2", side_key: "right", combatants: [ victim ] },
      round_number: 1,
      rng: Random.new(42)
    )

    fear_actions = phase[:actions].select { |row| row[:type] == "fear_check" }
    assert fear_actions.any?, "expected fear_check actions in phase"
    assert fear_actions.any? { |row| row[:details].any? { |line| line.include?("fear_check") } }
    assert phase[:events].any? { |line| line.match?(/страх|не атаку|не реша/i) }
  end

  test "mutual fear skips special assault checks" do
    left = combatant(entity_id: "a", x: 12, y: 12, facing: 0, melee: 5, abilities: [ "fear" ], morale: 5, side_index: 0,
                     contributors: { melee: [ { entity_id: "a", name: "A", kind: "unit", power: 5 } ], ranged: [], spell: [] })
    right = combatant(entity_id: "b", x: 14.2, y: 12, facing: 180, melee: 5, abilities: [ "fear" ], morale: 5, side_index: 1,
                      contributors: { melee: [ { entity_id: "b", name: "B", kind: "unit", power: 5 } ], ranged: [], spell: [] })

    phase = Attack.create_phase("melee", "Фаза боя")
    FearMelee.before_play!(
      phase: phase,
      acting_side: { player_id: "p1", combatants: [ left ] },
      target_side: { player_id: "p2", combatants: [ right ] },
      round_number: 1
    )

    assert_empty phase[:actions].select { |row| row[:type] == "fear_check" }
    refute FearMelee.blocked?(left)
    refute FearMelee.blocked?(right)
  end

  test "seeds wire breath shooting on bone dragon" do
    source = File.read(Rails.root.join("db/seeds.rb"))
    assert_match(/bone_dragon/, source)
    assert_match(/weapon_type:\s*"breath"/, source)
    assert_match(/return "breath" if attributes\.fetch\(:weapon_type\) == "breath"/, source)
  end

  private

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
