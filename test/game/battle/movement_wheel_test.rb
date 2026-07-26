require "test_helper"

class SimBattleMovementWheelTest < ActiveSupport::TestCase
  test "turning spends MV so a wide unit cannot fully face and close in one move" do
    actor = combatant(
      entity_id: "wide-1",
      name: "Копейщики",
      x: 8,
      y: 12,
      facing: 0,
      base_width: 4,
      base_depth: 1,
      movement: 3,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "center"
    )
    enemy = combatant(
      entity_id: "enemy-1",
      name: "Орки",
      x: 8,
      y: 20,
      facing: 270,
      base_width: 2,
      base_depth: 1,
      movement: 3,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "center",
      side_index: 1
    )

    acting_side = { player_id: "p1", combatants: [ actor ] }
    target_side = { player_id: "p2", combatants: [ enemy ] }
    expected = Sim::Geometry::Battlefield.apply_wheel(actor, 90, actor[:movement])

    phase = Sim::Battle::Phases::Movement.play(acting_side: acting_side, target_side: target_side)

    # width 4, MV 3 => partial arc wheel, no leftover forward march
    assert_in_delta expected[:facing], actor[:facing], 0.2
    assert_in_delta expected[:x], actor[:x], 0.05
    assert_in_delta expected[:y], actor[:y], 0.05
    refute_in_delta 8.0, actor[:x], 0.05
    assert phase[:actions].any? { |action| action[:summary].include?("wheel") }
    assert phase[:actions].any? { |action| action[:wheel].present? }
  end

  test "aligned unit spends full MV on travel" do
    actor = combatant(
      entity_id: "spear-1",
      name: "Копейщики",
      x: 8,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 1,
      movement: 3,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "center"
    )
    enemy = combatant(
      entity_id: "enemy-1",
      name: "Орки",
      x: 20,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 1,
      movement: 3,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "center",
      side_index: 1
    )

    acting_side = { player_id: "p1", combatants: [ actor ] }
    target_side = { player_id: "p2", combatants: [ enemy ] }

    Sim::Battle::Phases::Movement.play(acting_side: acting_side, target_side: target_side)

    assert_in_delta 0, actor[:facing], 0.001
    assert_in_delta 11.0, actor[:x], 0.05
  end

  test "right-side row advance keeps facing and does not remirror to 0" do
    actor = combatant(
      entity_id: "bot-marauders",
      name: "Мародеры",
      side_index: 1,
      x: 35,
      y: 19,
      facing: 180,
      base_width: 4,
      base_depth: 4,
      movement: 0,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "support",
      lane: "left"
    )
    enemy = combatant(
      entity_id: "enemy-1",
      name: "Воины",
      x: 12,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      row: "front",
      lane: "center"
    )

    Sim::Battle::Phases::Movement.play(
      acting_side: { player_id: "bot", combatants: [ actor ] },
      target_side: { player_id: "p1", combatants: [ enemy ] }
    )

    assert_equal "front", actor[:row]
    assert_in_delta 180.0, actor[:facing], 0.001
  end

  test "approach stops before overlapping an intervening enemy" do
    actor = combatant(
      entity_id: "knights",
      name: "Рыцари",
      x: 22,
      y: 12,
      facing: 180,
      base_width: 3,
      base_depth: 4,
      movement: 5,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "center",
      side_index: 1
    )
    blocker = combatant(
      entity_id: "blocker",
      name: "Мародеры",
      x: 16,
      y: 12,
      facing: 0,
      base_width: 4,
      base_depth: 4,
      movement: 3,
      melee: 4,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "center"
    )
    target = combatant(
      entity_id: "fleeing",
      name: "Бегущие",
      x: 10,
      y: 12,
      facing: 180,
      base_width: 1,
      base_depth: 1,
      movement: 3,
      melee: 4,
      ranged: 0,
      spell: 0,
      is_routing: true,
      row: "front",
      lane: "center"
    )

    Sim::Battle::Phases::Movement.play(
      acting_side: { player_id: "bot", combatants: [ actor ] },
      target_side: { player_id: "p1", combatants: [ blocker, target ] }
    )

    refute Sim::Geometry::Battlefield.rectangles_overlap?(actor, blocker)
    assert_operator Sim::Geometry::Battlefield.distance_between_units(actor, blocker), :>=, Sim::Battle::Phases::Movement::CONTACT - 0.05
  end

  def combatant(**overrides)
    {
      entity_id: "unit-1",
      name: "Unit",
      kind: "unit",
      side_index: 0,
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
      max_files: 2,
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
      abilities: []
    }.merge(overrides)
  end
end
