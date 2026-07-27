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
    assert phase[:actions].any? { |action| action[:wheel].present? }
    assert phase[:actions].any? { |action| action[:details].any? { |line| line.include?("wheel") } }
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
    assert_in_delta 35.0, actor[:x], 0.001
    assert_in_delta 19.0, actor[:y], 0.001
  end

  test "row advance keeps battlefield coordinates and never teleports backward" do
    actor = combatant(
      entity_id: "chaos-knights",
      name: "Рыцари Хаоса",
      x: 14.6,
      y: 12.9,
      facing: 2,
      base_width: 3,
      base_depth: 4,
      movement: 0,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "support",
      lane: "center"
    )
    enemy = combatant(
      entity_id: "enemy-1",
      name: "Тролли",
      x: 22,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      row: "front",
      lane: "center",
      side_index: 1
    )

    phase = Sim::Battle::Phases::Movement.play(
      acting_side: { player_id: "p1", combatants: [ actor ] },
      target_side: { player_id: "bot", combatants: [ enemy ] }
    )

    assert_equal "front", actor[:row]
    assert_in_delta 14.6, actor[:x], 0.001
    assert_in_delta 12.9, actor[:y], 0.001
    advance = phase[:actions].find { |action| action.dig(:maneuver, :kind) == "row_advance" }
    assert advance
    assert_in_delta 14.6, advance[:to][:x], 0.001
    assert_in_delta 12.9, advance[:to][:y], 0.001
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

  test "spaced column can march without clipping the ally behind" do
    # Gap keeps footprints outside melee contact so a corrective wheel/march is legal.
    front = combatant(
      entity_id: "front-swords",
      name: "Имперские мечники",
      x: 28,
      y: 12,
      facing: 180,
      base_width: 4,
      base_depth: 4,
      movement: 3,
      melee: 4,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "center",
      side_index: 1
    )
    rear = combatant(
      entity_id: "rear-swords",
      name: "Имперские мечники",
      x: 35,
      y: 12,
      facing: 180,
      base_width: 4,
      base_depth: 4,
      movement: 3,
      melee: 4,
      ranged: 0,
      spell: 0,
      row: "support",
      lane: "center",
      side_index: 1
    )
    enemy = combatant(
      entity_id: "enemy-1",
      name: "Мародеры",
      x: 12,
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

    phase = Sim::Battle::Phases::Movement.play(
      acting_side: { player_id: "bot", combatants: [ front, rear ] },
      target_side: { player_id: "p1", combatants: [ enemy ] }
    )

    assert phase[:actions].any? { |action| action[:actor_id] == "front-swords" }
    assert_operator front[:x], :<, 28
  end

  test "approach bypasses an intervening enemy blocker toward the target" do
    actor = combatant(
      entity_id: "knights",
      name: "Рыцари",
      x: 24,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
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
      x: 18,
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

    before = Sim::Geometry::Battlefield.distance_between_units(actor, target)
    phase = Sim::Battle::Phases::Movement.play(
      acting_side: { player_id: "bot", combatants: [ actor ] },
      target_side: { player_id: "p1", combatants: [ blocker, target ] }
    )
    after = Sim::Geometry::Battlefield.distance_between_units(actor, target)

    refute Sim::Geometry::Battlefield.rectangles_overlap?(actor, blocker)
    assert_operator after, :<, before
    assert_operator (actor[:y] - 12).abs, :>, 0.2
    assert phase[:actions].any? { |action|
      action.dig(:maneuver, :avoided) ||
        action.dig(:maneuver, :kind) == "bypass" ||
        action[:summary].include?("обходит") ||
        action[:details].any? { |line| line.include?("pathing_avoided=true") }
    }
  end

  test "co-moving allies do not force each other to wait or orbit" do
    actor = combatant(
      entity_id: "chaos-knights",
      name: "Рыцари Хаоса",
      x: 4,
      y: 12,
      facing: 0,
      base_width: 3,
      base_depth: 4,
      movement: 5,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "support",
      lane: "center",
      side_index: 0
    )
    ally = combatant(
      entity_id: "marauders",
      name: "Мародеры",
      x: 10,
      y: 12,
      facing: 0,
      base_width: 4,
      base_depth: 4,
      movement: 3,
      melee: 4,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "center",
      side_index: 0
    )
    enemy = combatant(
      entity_id: "trolls",
      name: "Каменные тролли",
      x: 28,
      y: 12,
      facing: 180,
      base_width: 3,
      base_depth: 3,
      movement: 3,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "center",
      side_index: 1
    )

    actor_start = actor[:x]
    ally_start = ally[:x]
    phase = Sim::Battle::Phases::Movement.play(
      acting_side: { player_id: "p1", combatants: [ actor, ally ] },
      target_side: { player_id: "bot", combatants: [ enemy ] }
    )

    assert phase[:actions].any? { |action| action[:actor_id] == "chaos-knights" }
    assert phase[:actions].any? { |action| action[:actor_id] == "marauders" }
    refute phase[:actions].any? { |action|
      action.dig(:maneuver, :avoided) ||
        action[:summary].include?("обходит") ||
        action[:summary].include?("ждёт прохода") ||
        action.dig(:maneuver, :blocked_by_ally)
    }
    assert_operator actor[:x], :>, actor_start + 1.0
    assert_operator ally[:x], :>, ally_start + 0.5
  end

  test "stationary allied blocker still stops approach without orbiting" do
    actor = combatant(
      entity_id: "chaos-knights",
      name: "Рыцари Хаоса",
      x: 4,
      y: 8,
      facing: 0,
      base_width: 3,
      base_depth: 4,
      movement: 5,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "support",
      lane: "center",
      side_index: 0
    )
    # Ranged ally is not in the mobile set, so it remains a simultaneous-phase obstacle.
    ally = combatant(
      entity_id: "archers",
      name: "Лучники",
      x: 10,
      y: 12,
      facing: 0,
      base_width: 4,
      base_depth: 4,
      movement: 3,
      melee: 1,
      ranged: 5,
      spell: 0,
      row: "front",
      lane: "center",
      side_index: 0
    )
    enemy = combatant(
      entity_id: "trolls",
      name: "Каменные тролли",
      x: 20,
      y: 12,
      facing: 180,
      base_width: 3,
      base_depth: 3,
      movement: 3,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "center",
      side_index: 1
    )

    start_y = actor[:y]
    phase = Sim::Battle::Phases::Movement.play(
      acting_side: { player_id: "p1", combatants: [ actor, ally ] },
      target_side: { player_id: "bot", combatants: [ enemy ] }
    )
    knight_actions = phase[:actions].select { |action| action[:actor_id] == "chaos-knights" }

    assert knight_actions.any?
    refute knight_actions.any? { |action| action.dig(:maneuver, :avoided) }
    refute knight_actions.any? { |action| action[:summary].include?("обходит") }
    assert knight_actions.any? { |action|
      action.dig(:maneuver, :blocked_by_ally) ||
        action.dig(:maneuver, :kind) == "blocked_by_ally" ||
        action[:summary].include?("союзником") ||
        action[:summary].include?("ждёт прохода")
    }
    assert_operator (actor[:y] - start_y).abs, :<, 1.5
    refute Sim::Geometry::Battlefield.rectangles_overlap?(actor, ally)
  end

  test "simultaneous movement is order-independent for co-movers" do
    build = lambda do |order|
      front = combatant(
        entity_id: "front",
        name: "Фронт",
        x: 12,
        y: 12,
        facing: 0,
        base_width: 2,
        base_depth: 2,
        movement: 4,
        melee: 4,
        ranged: 0,
        spell: 0,
        row: "front",
        lane: "center",
        side_index: 0
      )
      rear = combatant(
        entity_id: "rear",
        name: "Тыл",
        x: 6,
        y: 12,
        facing: 0,
        base_width: 2,
        base_depth: 2,
        movement: 4,
        melee: 4,
        ranged: 0,
        spell: 0,
        row: "support",
        lane: "center",
        side_index: 0
      )
      enemy = combatant(
        entity_id: "enemy",
        name: "Враг",
        x: 30,
        y: 12,
        facing: 180,
        base_width: 2,
        base_depth: 2,
        movement: 4,
        melee: 4,
        ranged: 0,
        spell: 0,
        row: "front",
        lane: "center",
        side_index: 1
      )
      combatants = order == :rear_first ? [ rear, front ] : [ front, rear ]
      Sim::Battle::Phases::Movement.play(
        acting_side: { player_id: "p1", combatants: combatants },
        target_side: { player_id: "bot", combatants: [ enemy ] }
      )
      {
        front_x: combatants.find { |entry| entry[:entity_id] == "front" }[:x],
        rear_x: combatants.find { |entry| entry[:entity_id] == "rear" }[:x]
      }
    end

    first = build.call(:front_first)
    second = build.call(:rear_first)
    assert_in_delta first[:front_x], second[:front_x], 0.001
    assert_in_delta first[:rear_x], second[:rear_x], 0.001
    assert_operator first[:rear_x], :>, 6.5
    assert_operator first[:front_x], :>, 12.5
  end

  test "plan_approach skips bypass when the blocker is an ally" do
    origin = combatant(
      entity_id: "boars",
      name: "Наездники на кабанах",
      x: 8,
      y: 12,
      facing: 0,
      base_width: 3,
      base_depth: 3,
      movement: 5,
      side_index: 0
    )
    ally = combatant(
      entity_id: "boyz",
      name: "Орки-бойзы",
      x: 14,
      y: 12,
      facing: 0,
      base_width: 4,
      base_depth: 4,
      side_index: 0
    )
    enemy = combatant(
      entity_id: "target",
      name: "Мародеры",
      x: 22,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      side_index: 1
    )

    plan = Sim::Battle::Pathing.plan_approach(
      origin: origin,
      goal_point: enemy,
      budget: 5,
      obstacles: [ origin, ally, enemy ],
      contact_id: enemy[:entity_id],
      goal_unit: enemy
    )

    assert plan[:blocked_by_ally]
    refute plan[:avoided]
    assert_equal "boyz", plan.dig(:blocker, :entity_id)
  end

  test "player log does not say обходит when soft-stopping on the charge target" do
    actor = combatant(
      entity_id: "boyz",
      name: "Орки-бойзы",
      x: 28,
      y: 16,
      facing: 180,
      base_width: 3,
      base_depth: 2,
      movement: 3,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "left",
      side_index: 1
    )
    target = combatant(
      entity_id: "warriors",
      name: "Воины Хаоса",
      x: 18,
      y: 16,
      facing: 0,
      base_width: 4,
      base_depth: 3,
      movement: 3,
      melee: 5,
      ranged: 0,
      spell: 0,
      row: "front",
      lane: "center",
      side_index: 0
    )

    phase = Sim::Battle::Phases::Movement.play(
      acting_side: { player_id: "bot", combatants: [ actor ] },
      target_side: { player_id: "p1", combatants: [ target ] }
    )
    action = phase[:actions].find { |entry| entry[:actor_id] == "boyz" }
    assert action, "expected boyz to move toward warriors"
    refute_includes action[:summary], "обходит"
    assert_includes action[:summary], "сближается с Воины Хаоса"
    assert action[:details].any? { |line| line.include?("MV budget=") }
    refute_includes action[:summary], "wheel"
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
