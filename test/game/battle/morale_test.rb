require "test_helper"

class SimBattleMoraleTest < ActiveSupport::TestCase
  test "deterministic dice from seed string" do
    assert_equal Sim::Battle::Phases::Morale.roll_dice("melee:1:0:unit-1"), Sim::Battle::Phases::Morale.roll_dice("melee:1:0:unit-1")
    assert_operator Sim::Battle::Phases::Morale.roll_dice("a"), :>=, 2
    assert_operator Sim::Battle::Phases::Morale.roll_dice("a"), :<=, 12
  end

  test "fear and combat score reduce threshold" do
    combatant = { entity_id: "u1", name: "Spearmen", kind: "unit", morale: 7, abilities: [], x: 5, y: 5 }
    allies = [ combatant ]
    enemies = [ { abilities: [ "fear" ], x: 6, y: 5 } ]
    check = Sim::Battle::Phases::Morale.resolve_check(
      combatant: combatant,
      allies: allies,
      enemies: enemies,
      round_number: 1,
      phase_type: "melee",
      combat_score_delta: 2,
      sequence: 0
    )

    assert_equal 4, check[:threshold]
  end

  test "breaking unit freely faces away from the threat, not a blind +180" do
    combatant = {
      entity_id: "u1",
      name: "Копейщики",
      kind: "unit",
      morale: 1,
      abilities: [],
      x: 10,
      y: 12,
      facing: 45,
      movement: 3,
      current_health: 8,
      max_health: 8,
      model_health: 1,
      models_remaining: 8,
      starting_models: 8,
      is_routing: false,
      base_width: 2,
      base_depth: 1,
      model_width: 1,
      model_depth: 1,
      frontage: 2,
      max_files: 2,
      files: 2,
      ranks: 1
    }
    # Threat is to the east; flee facing must be west (180), not 45+180=225.
    threat = { entity_id: "e1", current_health: 4, x: 14, y: 12, is_routing: false, abilities: [] }

    action = Sim::Battle::Phases::Morale.resolve_action(
      combatant: combatant,
      allies: [ combatant ],
      enemies: [ threat ],
      round_number: 1,
      phase_type: "melee",
      combat_score_delta: 20,
      sequence: 0,
      engaged_enemies: [ threat ]
    )

    assert combatant[:is_routing] || combatant[:current_health].to_i <= 0
    assert_includes action[:summary], "от угрозы"
    assert_in_delta 180, action[:actor_state_after][:facing], 0.001
    refute_in_delta 225, action[:actor_state_after][:facing], 0.5
    assert_includes action[:details].join(" "), "бесплатный разворот"
  end

  test "missile break faces away from shooters even with odd current facing" do
    combatant = {
      entity_id: "u1",
      name: "Копейщики",
      kind: "unit",
      morale: 1,
      abilities: [],
      x: 10,
      y: 12,
      facing: 43,
      movement: 3,
      current_health: 8,
      max_health: 8,
      model_health: 1,
      models_remaining: 8,
      starting_models: 8,
      is_routing: false,
      base_width: 2,
      base_depth: 1,
      model_width: 1,
      model_depth: 1,
      frontage: 2,
      max_files: 2,
      files: 2,
      ranks: 1
    }
    shooter = { entity_id: "e1", current_health: 4, x: 10, y: 18, is_routing: false, abilities: [] }

    action = Sim::Battle::Phases::Morale.resolve_action(
      combatant: combatant,
      allies: [ combatant ],
      enemies: [ shooter ],
      round_number: 1,
      phase_type: "shooting",
      combat_score_delta: 0,
      sequence: 0
    )

    assert action[:morale_check][:status_after]
    # Shooter is south of unit => flee north (270 in this coord system? facing 90 is +y/south)
    # heading from shooter(10,18) to unit(10,12) = atan2(-6, 0) = -90 => normalize 270
    assert_in_delta 270, action[:actor_state_after][:facing], 0.001
  end

  test "already routing unit does not about-face again on continued flee" do
    combatant = {
      entity_id: "u1",
      name: "Копейщики",
      kind: "unit",
      morale: 1,
      abilities: [],
      x: 10,
      y: 12,
      facing: 180,
      movement: 3,
      current_health: 8,
      max_health: 8,
      model_health: 1,
      models_remaining: 8,
      starting_models: 8,
      is_routing: true,
      base_width: 2,
      base_depth: 1,
      model_width: 1,
      model_depth: 1,
      frontage: 2,
      max_files: 2,
      files: 2,
      ranks: 1
    }

    action = Sim::Battle::Phases::Morale.resolve_action(
      combatant: combatant,
      allies: [ combatant ],
      enemies: [ { entity_id: "e1", current_health: 4, x: 14, y: 12, is_routing: false, abilities: [] } ],
      round_number: 2,
      phase_type: "start",
      combat_score_delta: 0,
      sequence: 0
    )

    assert_in_delta 180, action[:actor_state_after][:facing], 0.001
    refute_includes action[:details].join(" "), "flee_facing="
    refute_includes action[:details].join(" "), "about_faced=true"
  end

  test "rally keeps flee facing and does not freely turn toward the enemy" do
    combatant = {
      entity_id: "u1",
      name: "Аутрайдеры",
      kind: "unit",
      morale: 12,
      abilities: [],
      x: 33.5,
      y: 14.5,
      facing: 2,
      movement: 5,
      current_health: 4,
      max_health: 6,
      model_health: 1,
      models_remaining: 4,
      starting_models: 6,
      is_routing: true,
      base_width: 3,
      base_depth: 4,
      model_width: 1,
      model_depth: 1,
      frontage: 3,
      max_files: 5,
      files: 3,
      ranks: 2
    }
    enemy = { entity_id: "e1", current_health: 8, x: 12, y: 12, facing: 0, is_routing: false, abilities: [] }

    action = Sim::Battle::Phases::Morale.resolve_action(
      combatant: combatant,
      allies: [ combatant ],
      enemies: [ enemy ],
      round_number: 2,
      phase_type: "start",
      combat_score_delta: 0,
      sequence: 0
    )

    assert action[:morale_check][:passed]
    refute combatant[:is_routing]
    assert_includes action[:summary], "собирается с духом"
    assert_in_delta 2.0, combatant[:facing], 0.001
    refute_in_delta Sim::Geometry::Battlefield.heading_to(combatant, enemy), combatant[:facing], 5
  end

  test "routing unit does not orbit an allied blocker" do
    combatant = {
      entity_id: "u1",
      name: "Копейщики",
      kind: "unit",
      morale: 1,
      abilities: [],
      x: 10,
      y: 12,
      facing: 180,
      movement: 4,
      current_health: 8,
      max_health: 8,
      model_health: 1,
      models_remaining: 8,
      starting_models: 8,
      is_routing: true,
      side_index: 0,
      base_width: 2,
      base_depth: 4,
      model_width: 1,
      model_depth: 1,
      frontage: 2,
      max_files: 2,
      files: 2,
      ranks: 4
    }
    blocker = {
      entity_id: "ally-1",
      name: "Союзники",
      current_health: 8,
      x: 4,
      y: 12,
      facing: 0,
      side_index: 0,
      base_width: 4,
      base_depth: 4,
      is_routing: false,
      abilities: []
    }

    action = Sim::Battle::Phases::Morale.resolve_action(
      combatant: combatant,
      allies: [ combatant, blocker ],
      enemies: [ { entity_id: "e1", current_health: 4, x: 22, y: 12, facing: 180, is_routing: false, abilities: [] } ],
      round_number: 2,
      phase_type: "start",
      combat_score_delta: 0,
      sequence: 0
    )

    refute Sim::Geometry::Battlefield.rectangles_overlap?(combatant, blocker)
    refute_match(/обходит/, action[:summary])
    assert_includes action[:details].join(" "), "avoided=false"
  end

  test "fleeing unit does not slide around another unit with the same name" do
    fleeing = {
      entity_id: "unit-5",
      name: "Гоблины-лучники",
      kind: "unit",
      morale: 1,
      abilities: [],
      x: 30.5,
      y: 11.0,
      facing: 180,
      movement: 4,
      current_health: 4,
      max_health: 8,
      model_health: 1,
      models_remaining: 4,
      starting_models: 8,
      is_routing: false,
      side_index: 1,
      base_width: 4,
      base_depth: 2,
      model_width: 1,
      model_depth: 1,
      frontage: 4,
      max_files: 5,
      files: 4,
      ranks: 1
    }
    friend = {
      entity_id: "unit-8",
      name: "Гоблины-лучники",
      current_health: 8,
      x: 35.0,
      y: 11.0,
      facing: 180,
      side_index: 1,
      base_width: 4,
      base_depth: 3,
      is_routing: false,
      abilities: []
    }

    action = Sim::Battle::Phases::Morale.resolve_action(
      combatant: fleeing,
      allies: [ fleeing, friend ],
      enemies: [ { entity_id: "e1", current_health: 4, x: 12, y: 11, facing: 0, is_routing: false, abilities: [] } ],
      round_number: 2,
      phase_type: "magic",
      combat_score_delta: 0,
      sequence: 0,
      engaged_enemies: []
    )

    assert fleeing[:is_routing] || fleeing[:current_health].to_i <= 0
    refute_match(/обходит/, action[:summary])
    assert_includes action[:details].join(" "), "avoided=false"
  end
end
