require "test_helper"

class SimBattleMissileChoiceTest < ActiveSupport::TestCase
  test "actor with only ranged chooses shooting" do
    actor = missile_actor(ranged: 5, spell: 0, skill: 4, weapon_type: "ranged")
    enemies = [ enemy(armor_type: "light", models_remaining: 10) ]

    choice = Sim::Battle::Phases::Missile.choose_action(actor, enemies, enemies, 1)

    assert_equal "shooting", choice[:attack_type]
  end

  test "actor with only spell chooses magic" do
    actor = missile_actor(ranged: 0, spell: 5, skill: 4, weapon_type: "slash")
    enemies = [ enemy(armor_type: "light", models_remaining: 10) ]

    choice = Sim::Battle::Phases::Missile.choose_action(actor, enemies, enemies, 1)

    assert_equal "magic", choice[:attack_type]
  end

  test "prefers magic when expected damage is higher" do
    actor = missile_actor(ranged: 1, spell: 6, skill: 2, weapon_type: "ranged", abilities: [])
    enemies = [ enemy(armor_type: "magic", models_remaining: 8) ]

    choice = Sim::Battle::Phases::Missile.choose_action(actor, enemies, enemies, 1)

    assert_equal "magic", choice[:attack_type]
  end

  test "prefers shooting when demolish into machine armor beats magic" do
    actor = missile_actor(
      ranged: 8,
      spell: 1,
      skill: 6,
      weapon_type: "demolish",
      abilities: [ "machine" ],
      shooting_template: "blast"
    )
    enemies = [ enemy(armor_type: "machine", models_remaining: 2, current_health: 8, max_health: 8) ]

    choice = Sim::Battle::Phases::Missile.choose_action(actor, enemies, enemies, 1)

    assert_equal "shooting", choice[:attack_type]
  end

  test "shared plan lets each actor act once across magic and shooting" do
    host = {
      entity_id: "hero-1",
      name: "Вампир",
      kind: "hero",
      side_key: "left",
      lane: "center",
      row: "support",
      x: 0,
      y: 0,
      facing: 0,
      base_width: 1,
      base_depth: 1,
      model_width: 1,
      model_depth: 1,
      frontage: 1,
      max_files: 1,
      files: 1,
      ranks: 1,
      current_health: 4,
      max_health: 4,
      model_health: 4,
      models_remaining: 1,
      starting_models: 1,
      is_routing: false,
      initiative: 5,
      skill: 5,
      morale: 7,
      melee: 5,
      ranged: 3,
      spell: 4,
      armor_type: "heavy",
      weapon_type: "slash",
      abilities: [ "wizard" ],
      shooting_range: 10,
      spell_range: 8,
      shooting_template: "single",
      spell_template: "blast",
      requires_line_of_sight: true,
      attacks: 3,
      missile_attacks: 1,
      contributors: {
        melee: [],
        ranged: [
          {
            entity_id: "hero-1",
            name: "Вампир",
            kind: "hero",
            power: 4,
            ranged: 3,
            spell: 4,
            skill: 5,
            weapon_type: "slash",
            abilities: [ "wizard" ],
            shooting_range: 10,
            spell_range: 8,
            shooting_template: "single",
            spell_template: "blast",
            requires_line_of_sight: true,
            missile_attacks: 1,
            initiative: 5,
            experience_gain: 0
          }
        ]
      }
    }
    target = enemy(entity_id: "enemy-1", armor_type: "medium", models_remaining: 12, current_health: 12, x: 4, y: 0)
    acting_side = { player_id: "p1", player_name: "A", combatants: [ host ] }
    target_side = { player_id: "p2", player_name: "B", combatants: [ target ] }
    rng = Sim::Rng::Seeded.new(7)

    plan = Sim::Battle::Phases::Missile.plan(
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1
    )

    assert_equal 1, plan.size
    assert_includes %w[magic shooting], plan.first[:attack_type]

    magic = Sim::Battle::Phases::AttackResolution.create_phase("magic", "Фаза магии")
    shooting = Sim::Battle::Phases::AttackResolution.create_phase("shooting", "Фаза стрельбы")
    Sim::Battle::Phases::Missile.play_planned!(
      phase: magic,
      plan: plan,
      attack_type: "magic",
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1,
      rng: rng
    )
    Sim::Battle::Phases::Missile.play_planned!(
      phase: shooting,
      plan: plan,
      attack_type: "shooting",
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1,
      rng: rng
    )

    total_strikes = magic[:actions].size + shooting[:actions].size
    assert_operator total_strikes, :>=, 1
    assert(magic[:actions].empty? || shooting[:actions].empty?)
  end

  test "host and attached hero each choose independently" do
    host_contributor = {
      entity_id: "unit-1",
      name: "Лучники",
      kind: "unit",
      power: 4,
      ranged: 4,
      spell: 0,
      skill: 3,
      weapon_type: "ranged",
      abilities: [ "ranged" ],
      shooting_template: "volley",
      spell_template: "single",
      requires_line_of_sight: true,
      missile_attacks: 1,
      initiative: 4,
      experience_gain: 0
    }
    hero_contributor = {
      entity_id: "hero-1",
      name: "Волшебник",
      kind: "hero",
      power: 5,
      ranged: 1,
      spell: 5,
      skill: 5,
      weapon_type: "magic",
      abilities: [ "wizard" ],
      shooting_template: "single",
      spell_template: "blast",
      requires_line_of_sight: true,
      missile_attacks: 1,
      initiative: 5,
      attached_slot: "front",
      experience_gain: 0
    }
    host = {
      entity_id: "unit-1",
      name: "Лучники",
      kind: "unit",
      current_health: 10,
      is_routing: false,
      initiative: 4,
      ranged: 5,
      spell: 5,
      x: 0,
      y: 0,
      facing: 0,
      base_width: 2,
      base_depth: 1,
      lane: "center",
      row: "support",
      abilities: [ "ranged" ],
      contributors: { melee: [], ranged: [ host_contributor, hero_contributor ] }
    }
    enemies = [ enemy(armor_type: "light", models_remaining: 10) ]
    acting_side = { player_id: "p1", player_name: "A", combatants: [ host ] }
    target_side = { player_id: "p2", player_name: "B", combatants: enemies }

    plan = Sim::Battle::Phases::Missile.plan(
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1
    )

    assert_equal 2, plan.size
    by_actor = plan.index_by { |entry| entry[:actor_id] }
    assert_equal "shooting", by_actor.fetch("unit-1")[:attack_type]
    assert_equal "magic", by_actor.fetch("hero-1")[:attack_type]
  end

  test "spell casting facade owns magic hit chance" do
    assert_equal 1.0, Sim::Battle::SpellCasting.hit_chance({ spell: 1 }, { skill: 9 })
    assert_equal false, Sim::Battle::SpellCasting.enabled_for?({ spell: 0 })
    assert_equal true, Sim::Battle::SpellCasting.enabled_for?({ spell: 2 })
  end

  test "melee attacks do not multiply magic strikes unless missile_attacks set" do
    host = {
      entity_id: "hero-1",
      name: "Демонический принц",
      kind: "hero",
      side_key: "left",
      lane: "center",
      row: "support",
      x: 0,
      y: 0,
      facing: 0,
      base_width: 1,
      base_depth: 1,
      model_width: 1,
      model_depth: 1,
      frontage: 1,
      max_files: 1,
      files: 1,
      ranks: 1,
      current_health: 5,
      max_health: 5,
      model_health: 5,
      models_remaining: 1,
      starting_models: 1,
      is_routing: false,
      initiative: 5,
      skill: 6,
      morale: 7,
      melee: 5,
      ranged: 3,
      spell: 5,
      attacks: 3,
      missile_attacks: 1,
      armor_type: "magic",
      weapon_type: "magic",
      abilities: [ "wizard" ],
      shooting_range: 10,
      spell_range: 8,
      shooting_template: "single",
      spell_template: "blast",
      requires_line_of_sight: true,
      contributors: {
        melee: [],
        ranged: [
          {
            entity_id: "hero-1",
            name: "Демонический принц",
            kind: "hero",
            power: 5,
            ranged: 3,
            spell: 5,
            skill: 6,
            weapon_type: "magic",
            abilities: [ "wizard" ],
            shooting_template: "single",
            spell_template: "blast",
            requires_line_of_sight: true,
            missile_attacks: 1,
            initiative: 5,
            experience_gain: 0
          }
        ]
      }
    }
    target = enemy(entity_id: "enemy-1", armor_type: "medium", models_remaining: 12, current_health: 12, x: 4, y: 0)
    acting_side = { player_id: "p1", player_name: "A", combatants: [ host ] }
    target_side = { player_id: "p2", player_name: "B", combatants: [ target ] }
    plan = [
      {
        attack_type: "magic",
        target_id: target[:entity_id],
        vector: "front",
        host_id: "hero-1",
        actor_id: "hero-1"
      }
    ]
    phase = Sim::Battle::Phases::AttackResolution.create_phase("magic", "Фаза магии")

    Sim::Battle::Phases::Missile.play_planned!(
      phase: phase,
      plan: plan,
      attack_type: "magic",
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1,
      rng: Sim::Rng::Seeded.new(1)
    )

    assert_equal 1, phase[:actions].size
  end

  private

  def missile_actor(ranged:, spell:, skill:, weapon_type:, abilities: [], shooting_template: "single")
    {
      entity_id: "actor-host",
      host_id: "actor-host",
      actor_id: "actor-1",
      actor_name: "Стрелок",
      actor_role: "hero",
      key: "actor-host:actor-1",
      name: "Стрелок",
      kind: "hero",
      x: 0,
      y: 0,
      facing: 0,
      base_width: 1,
      base_depth: 1,
      lane: "center",
      row: "support",
      ranged: ranged,
      spell: spell,
      skill: skill,
      weapon_type: weapon_type,
      abilities: abilities,
      targeting_abilities: abilities,
      shooting_range: 12,
      spell_range: 8,
      shooting_template: shooting_template,
      spell_template: "blast",
      requires_line_of_sight: true,
      missile_attacks: 1,
      initiative: 5,
      is_routing: false,
      current_health: 4
    }
  end

  def enemy(armor_type:, models_remaining:, current_health: nil, max_health: nil, entity_id: "enemy-1", x: 5, y: 0)
    health = current_health || models_remaining
    {
      entity_id: entity_id,
      name: "Цель",
      kind: "unit",
      armor_type: armor_type,
      abilities: [],
      morale: 6,
      models_remaining: models_remaining,
      starting_models: models_remaining,
      current_health: health,
      max_health: max_health || health,
      model_health: 1,
      model_width: 0.5,
      model_depth: 0.5,
      frontage: 4,
      max_files: 4,
      files: [ models_remaining, 4 ].min,
      ranks: 1,
      x: x,
      y: y,
      facing: 180,
      base_width: 2,
      base_depth: 1,
      lane: "center",
      row: "front",
      is_routing: false
    }
  end
end
