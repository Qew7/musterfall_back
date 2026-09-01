require "test_helper"

class SimBattleCommonShootingTest < ActiveSupport::TestCase
  Common = Sim::Battle::Rules::Common::Shooting
  Attack = Sim::Battle::Phases::AttackResolution
  Rules = Sim::Battle::Rules

  test "common template is registered and applies" do
    assert_includes Rules.for(:shooting).rules, Common
    assert_equal Common, Rules.for(:shooting).find_applicable({ shooting_template: "common" }, "shooting")
  end

  test "front rank models cap attempts at files not total models" do
    host = archer_host(files: 4, ranks: 3, models_remaining: 8, missile_attacks: 1)

    assert_equal 4, Common.front_rank_models(host)
    assert_equal 4, Common.shooting_attempts(host, host)
  end

  test "shrunk unit uses remaining models when fewer than files" do
    host = archer_host(files: 5, ranks: 2, models_remaining: 2, missile_attacks: 1)

    assert_equal 2, Common.front_rank_models(host)
    assert_equal 2, Common.shooting_attempts(host, host)
  end

  test "each front rank model rolls once per missile_attacks stat" do
    host = archer_host(files: 3, ranks: 2, models_remaining: 6, missile_attacks: 2)

    assert_equal 6, Common.shooting_attempts(host, host)
  end

  test "resolve rolls one hit check per front rank attack" do
    host = archer_host(files: 4, ranks: 1, models_remaining: 4, missile_attacks: 1)
    target = enemy(current_health: 20, max_health: 20, armor_type: "light")
    acting_side = { combatants: [ host ] }
    target_side = { combatants: [ target ] }
    phase = Attack.create_phase("shooting", "стрельба")
    actor = Sim::Battle::Decisions::MissileChoice.build_actor(host, host.dig(:contributors, :ranged).first)
    victims = [ { target: target, multiplier: 1 } ]

    Common.resolve_missile_strike!(
      phase: phase,
      actor: actor,
      host: host,
      profile: actor,
      vector: "front",
      victims: victims,
      attack_type: "shooting",
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1,
      blockers: [],
      rng: always_miss_rng,
      terrain: []
    )

    assert phase[:events].any? { |event| event.include?("0 из 4 атак") }
    miss = phase[:actions].find { |action| action[:damage].to_i.zero? }
    assert miss, "expected miss action in phase log"
    assert_match(/0 из 4 атак/, miss[:summary])
  end

  test "catalog seeds blast for empire cannon and volley for handgunners" do
    load Rails.root.join("db/seeds.rb")
    Sim::Catalog::Loader.reset!
    catalog = Sim::Catalog::Loader.load

    assert_equal "blast", catalog.template("great_cannon")[:shooting_template]
    assert_equal 10, catalog.template("great_cannon")[:shooting_range]
    assert_includes catalog.template("great_cannon")[:abilities], "heavyBlast"
    assert_includes catalog.template("inferno_cannon")[:abilities], "antiFlying"
    assert_equal "line", catalog.template("inferno_cannon")[:shooting_template]
    assert_equal "volley", catalog.template("handgunners")[:shooting_template]
  end

  test "catalog seeds common template for bow units" do
    load Rails.root.join("db/seeds.rb")
    Sim::Catalog::Loader.reset!
    catalog = Sim::Catalog::Loader.load
    %w[goblin_archers grove_archers outriders].each do |key|
      assert_equal "common", catalog.template(key)[:shooting_template], key
    end
  end

  test "volley resolve rolls one hit check per front rank model per victim" do
    Volley = Sim::Battle::Rules::Volley::Shooting
    host = archer_host(files: 5, ranks: 2, models_remaining: 10, missile_attacks: 1)
    host[:shooting_template] = "volley"
    host.dig(:contributors, :ranged).first[:shooting_template] = "volley"
    primary = enemy(entity_id: "primary", x: 10, y: 0, current_health: 20, max_health: 20)
    secondary = enemy(entity_id: "secondary", x: 10, y: 1, current_health: 20, max_health: 20)
    acting_side = { combatants: [ host ] }
    target_side = { combatants: [ primary, secondary ] }
    phase = Attack.create_phase("shooting", "стрельба")
    actor = Sim::Battle::Decisions::MissileChoice.build_actor(host, host.dig(:contributors, :ranged).first)
    victims = Volley.attack_victims(actor, primary, target_side[:combatants])

    assert_equal 2, victims.length
    Volley.resolve_missile_strike!(
      phase: phase,
      actor: actor,
      host: host,
      profile: actor,
      primary: primary,
      vector: "front",
      victims: victims,
      attack_type: "shooting",
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1,
      blockers: [],
      rng: always_miss_rng,
      terrain: []
    )

    assert phase[:events].any? { |event| event.include?("0 из 5 атак") }
  end

  private

  def archer_host(files:, ranks:, models_remaining:, missile_attacks:)
    {
      entity_id: "unit-archers",
      name: "Лучники",
      kind: "unit",
      x: 0,
      y: 0,
      facing: 0,
      files: files,
      ranks: ranks,
      models_remaining: models_remaining,
      current_health: models_remaining,
      model_health: 1,
      attacks: 1,
      missile_attacks: missile_attacks,
      ranged: 4,
      skill: 3,
      weapon_type: "ranged",
      shooting_template: "common",
      abilities: [ "ranged" ],
      contributors: {
        ranged: [
          {
            entity_id: "unit-archers",
            name: "Лучники",
            kind: "unit",
            ranged: 4,
            spell: 0,
            skill: 3,
            weapon_type: "ranged",
            abilities: [ "ranged" ],
            shooting_template: "common",
            missile_attacks: missile_attacks,
            initiative: 4
          }
        ]
      }
    }
  end

  def enemy(**overrides)
    {
      entity_id: "enemy-1",
      name: "Target",
      kind: "unit",
      x: 10,
      y: 0,
      facing: 180,
      current_health: 10,
      max_health: 10,
      model_health: 1,
      models_remaining: 10,
      armor_type: "medium",
      skill: 3,
      abilities: []
    }.merge(overrides)
  end

  def always_miss_rng
    Object.new.tap do |rng|
      rng.define_singleton_method(:rand) { 1.0 }
    end
  end
end
