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
    assert_includes action[:details].join(" "), "Бесплатный разворот от угрозы"
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
    refute_includes action[:details].join(" "), "Бесплатный разворот"
  end
end
