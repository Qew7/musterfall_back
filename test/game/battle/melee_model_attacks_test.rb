require "test_helper"

class SimBattleMeleeModelAttacksTest < ActiveSupport::TestCase
  Attack = Sim::Battle::Phases::AttackResolution

  test "melee rolls once per fighting model and applies total damage once" do
    attacker = combatant(
      entity_id: "dryads",
      name: "Дриады",
      x: 10,
      y: 12,
      facing: 0,
      files: 4,
      ranks: 2,
      model_width: 1,
      model_depth: 1,
      base_width: 4,
      base_depth: 2,
      attacks: 1,
      melee: 4,
      contributors: {
        melee: [ { entity_id: "dryads", name: "Дриады", kind: "unit", power: 4 } ],
        ranged: [],
        spell: []
      }
    )
    defender = combatant(
      entity_id: "reavers",
      name: "Отряд грабителей",
      x: 14.2,
      y: 12,
      facing: 180,
      side_index: 1,
      files: 4,
      ranks: 2,
      model_width: 1,
      model_depth: 1,
      base_width: 4,
      base_depth: 2,
      current_health: 20,
      max_health: 20,
      models_remaining: 10
    )

    engaged = Attack.engaged_model_count(attacker, defender)
    assert_operator engaged, :>=, 2

    per_hit = Attack.melee_entries(attacker, defender, "front", 1).first[:damage]
    health_before = defender[:current_health]
    rolls = Array.new(engaged, 0.1) + [ 0.9 ]
    in_contact = Attack.defender_engaged_model_count(attacker, defender)
    expected_damage = [
      per_hit * engaged,
      Attack.melee_kill_damage_cap(defender, in_contact)
    ].min

    phase = Attack.create_phase("melee", "Фаза боя")
    Attack.resolve_melee_strike!(
      phase: phase,
      attacker: attacker,
      target: defender,
      vector: "front",
      acting_side: { combatants: [ attacker ] },
      target_side: { combatants: [ defender ] },
      round_number: 1,
      rng: seq_rng(rolls)
    )

    action = phase[:actions].find { |row| row[:type] == "melee" }
    assert action, "expected one melee action"
    assert_equal engaged, action[:attacks_attempted]
    assert_equal engaged, action[:hits_landed]
    assert_equal expected_damage, action[:damage]
    assert_equal health_before - expected_damage, defender[:current_health]
    assert_equal 1, phase[:actions].count { |row| row[:type] == "melee" }
    assert_match(/попало #{engaged} из #{engaged} атак/, action[:summary])
  end

  test "melee logs misses when no fighting model hits" do
    attacker = combatant(
      entity_id: "dryads",
      x: 10,
      y: 12,
      facing: 0,
      files: 4,
      ranks: 2,
      model_width: 1,
      model_depth: 1,
      base_width: 4,
      base_depth: 2,
      attacks: 1,
      contributors: {
        melee: [ { entity_id: "dryads", name: "Дриады", kind: "unit", power: 4 } ],
        ranged: [],
        spell: []
      }
    )
    defender = combatant(
      entity_id: "reavers",
      x: 14.2,
      y: 12,
      facing: 180,
      side_index: 1,
      files: 4,
      ranks: 2,
      model_width: 1,
      model_depth: 1,
      base_width: 4,
      base_depth: 2
    )
    engaged = Attack.engaged_model_count(attacker, defender)

    phase = Attack.create_phase("melee", "Фаза боя")
    Attack.resolve_melee_strike!(
      phase: phase,
      attacker: attacker,
      target: defender,
      vector: "front",
      acting_side: { combatants: [ attacker ] },
      target_side: { combatants: [ defender ] },
      round_number: 1,
      rng: seq_rng(Array.new(engaged, 0.9))
    )

    assert_empty phase[:actions]
    assert_match(/попало 0 из #{engaged} атак/, phase[:events].last)
  end

  test "melee cannot kill more defender models than are in contact" do
    attacker = combatant(
      entity_id: "dryads",
      x: 10,
      y: 12,
      facing: 0,
      files: 4,
      ranks: 2,
      model_width: 1,
      model_depth: 1,
      base_width: 4,
      base_depth: 2,
      attacks: 3,
      melee: 8,
      contributors: {
        melee: [ { entity_id: "dryads", name: "Дриады", kind: "unit", power: 8 } ],
        ranged: [],
        spell: []
      }
    )
    defender = combatant(
      entity_id: "reavers",
      x: 14.2,
      y: 12,
      facing: 180,
      side_index: 1,
      files: 8,
      ranks: 2,
      model_width: 1,
      model_depth: 1,
      base_width: 8,
      base_depth: 2,
      current_health: 16,
      max_health: 16,
      models_remaining: 16,
      armor_type: "light"
    )

    in_contact = Attack.defender_engaged_model_count(attacker, defender)
    assert_operator in_contact, :>=, 2

    attempts = Attack.engaged_model_count(attacker, defender) * attacker[:attacks]
    phase = Attack.create_phase("melee", "Фаза боя")
    Attack.resolve_melee_strike!(
      phase: phase,
      attacker: attacker,
      target: defender,
      vector: "front",
      acting_side: { combatants: [ attacker ] },
      target_side: { combatants: [ defender ] },
      round_number: 1,
      rng: seq_rng(Array.new(attempts, 0.1))
    )

    action = phase[:actions].find { |row| row[:type] == "melee" }
    assert action
    models_lost = 16 - defender[:models_remaining]
    assert_operator models_lost, :<=, in_contact
    assert_operator action[:damage], :>, 0
    uncapped = action[:hits_landed] * Attack.melee_entries(attacker, defender, "front", 1).first[:damage]
    assert_operator uncapped, :>, action[:damage] if action[:hits_landed] > in_contact
  end

  test "melee strike records terrain_delta on the persisted phase action" do
    dryad = combatant(
      entity_id: "dryad",
      name: "Дриады",
      abilities: [ "forestkin" ],
      x: 10,
      y: 12,
      facing: 0,
      files: 2,
      ranks: 1,
      contributors: {
        melee: [ { entity_id: "dryad", name: "Дриады", kind: "unit", power: 4 } ],
        ranged: [],
        spell: []
      }
    )
    defender = combatant(
      entity_id: "foe",
      name: "Отряд грабителей",
      x: 14.2,
      y: 12,
      facing: 180,
      side_index: 1,
      files: 2,
      ranks: 1
    )
    terrain = []
    phase = Attack.create_phase("melee", "Фаза боя")

    Attack.resolve_melee_strike!(
      phase: phase,
      attacker: dryad,
      target: defender,
      vector: "front",
      acting_side: { combatants: [ dryad ] },
      target_side: { combatants: [ defender ] },
      round_number: 1,
      rng: seq_rng([ 0.1 ]),
      terrain: terrain
    )

    action = phase[:actions].find { |row| row[:type] == "melee" }
    assert action, "expected one melee action"
    assert_equal 1, Array(action[:terrain_delta]).length
    assert_equal "add", action[:terrain_delta].first[:operation]
    assert_equal "forest", action[:terrain_delta].first[:feature][:type]
    assert_equal 1, terrain.length
    assert_match(/лес прорастает/, action[:summary])
  end

  test "melee kill cap respects multi-wound models" do
    assert_equal 7, Attack.melee_kill_damage_cap({ current_health: 10, model_health: 2 }, 3)
    assert_equal 3, Attack.melee_kill_damage_cap({ current_health: 10, model_health: 2 }, 1)
  end

  def seq_rng(values)
    rolls = values.dup
    Object.new.tap do |rng|
      rng.define_singleton_method(:rand) { rolls.shift || 1.0 }
    end
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
      attacks: 1,
      missile_attacks: 1,
      shooting_template: "single",
      spell_template: "single",
      requires_line_of_sight: true,
      contributors: { melee: [], ranged: [], spell: [] },
      attached_heroes: []
    }.merge(overrides)
  end
end
