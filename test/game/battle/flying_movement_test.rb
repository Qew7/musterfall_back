require "test_helper"

class SimBattleFlyingMovementTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  CONTACT = Sim::Battle::Pathing::CONTACT
  ENGAGE = Sim::Battle::Pathing::ENGAGE
  MovementPhase = Sim::Battle::Phases::Movement
  DecisionsMovement = Sim::Battle::Decisions::Movement
  Flying = Sim::Battle::Rules::Flying::Movement
  Ground = Sim::Battle::Rules::Ground::Movement

  test "planner_for dispatches flying ability to Flying and others to Ground" do
    flyer = combatant(abilities: [ "flying" ], melee: 5)
    walker = combatant(abilities: [], melee: 5)

    assert_equal Flying, DecisionsMovement.planner_for(flyer)
    assert_equal Ground, DecisionsMovement.planner_for(walker)
  end

  test "seeds define flying on the four roster templates" do
    source = File.read(Rails.root.join("db/seeds.rb"))
    assert_match(/key:\s*"flying"/, source)
    assert_match(/griffon_marshal.*flying/m, source)
    assert_match(/daemon_prince.*flying/m, source)
    assert_match(/bone_dragon/, source)
    assert_match(/grove_hawk/, source)
    assert_includes source, '"flying"'
  end

  test "setup leaps behind the furthest enemy and lands clear of all bases" do
    flyer = combatant(
      entity_id: "flyer",
      name: "Ястреб",
      x: 8.0,
      y: 12.0,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 5,
      ranged: 0,
      spell: 0,
      movement: 8,
      abilities: [ "flying", "monster" ]
    )
    near = combatant(
      entity_id: "near",
      name: "Ближний",
      x: 12.0,
      y: 10.0,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )
    far = combatant(
      entity_id: "far",
      name: "Дальний",
      x: 14.0,
      y: 12.0,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )

    refute DecisionsMovement.engaged_with_any?(flyer, [ near, far ])
    assert_operator BF.distance_between_units(flyer, far), :>, BF.distance_between_units(flyer, near)

    entries = DecisionsMovement.plan_melee_entries([ flyer ], [ near, far ])
    assert_equal "far", entries.first[:nearest][:entity_id]
    assert_includes %i[flyer_setup_rear flyer_setup_flank], entries.first[:approach_mode]

    MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ flyer ] },
      target_side: { player_id: "p2", combatants: [ near, far ] }
    )

    [ near, far ].each do |unit|
      assert_operator BF.distance_between_units(flyer, unit), :>=, CONTACT,
        "setup landing must stay clear of #{unit[:entity_id]}"
    end
    assert BF.in_front_arc?(flyer, far, flyer[:facing]), "flyer should face the setup target"
    assert_includes %w[rear flank], BF.classify_attack_vector(flyer, far)
  end

  test "setup prefers rear over flank when MV reaches the rear point" do
    flyer = combatant(
      entity_id: "flyer",
      x: 16.0,
      y: 12.0,
      facing: 90,
      base_width: 1,
      base_depth: 1,
      melee: 5,
      movement: 5,
      abilities: [ "flying" ]
    )
    enemy = combatant(
      entity_id: "enemy",
      x: 18.0,
      y: 12.0,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )

    entries = DecisionsMovement.plan_melee_entries([ flyer ], [ enemy ])
    assert_equal 1, entries.size
    assert_equal "rear", entries.first[:contact_slot]
    assert_equal :flyer_setup_rear, entries.first[:approach_mode]
  end

  test "blocker on the line does not stop a flyer leap" do
    flyer = combatant(
      entity_id: "flyer",
      x: 8.0,
      y: 12.0,
      facing: 180,
      base_width: 1,
      base_depth: 1,
      melee: 5,
      movement: 8,
      abilities: [ "flying" ]
    )
    blocker = combatant(
      entity_id: "blocker",
      x: 12.0,
      y: 12.0,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      movement: 0
    )
    enemy = combatant(
      entity_id: "enemy",
      x: 14.0,
      y: 12.0,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )

    refute DecisionsMovement.engaged_with_any?(flyer, [ enemy ])
    start_x = flyer[:x]
    MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ flyer, blocker ] },
      target_side: { player_id: "p2", combatants: [ enemy ] }
    )

    assert_operator flyer[:x], :>, start_x + 1.0, "flyer should leap past the blocker"
    assert_operator BF.distance_between_units(flyer, blocker), :>=, CONTACT
    assert_operator BF.distance_between_units(flyer, enemy), :>=, CONTACT
  end

  test "charge leaps into ENGAGE when target is in arc within MV" do
    enemy = combatant(
      entity_id: "enemy",
      x: 16.0,
      y: 12.0,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )
    # Sit on the enemy rear line, facing them — charge eligible this turn.
    flyer = combatant(
      entity_id: "flyer",
      x: 19.5,
      y: 12.0,
      facing: 180,
      base_width: 1,
      base_depth: 1,
      melee: 5,
      movement: 5,
      abilities: [ "flying" ]
    )

    assert BF.in_front_arc?(flyer, enemy, flyer[:facing])
    assert_operator BF.distance_between_units(flyer, enemy), :<=, flyer[:movement]
    assert_equal "rear", BF.classify_attack_vector(flyer, enemy)

    entries = DecisionsMovement.plan_melee_entries([ flyer ], [ enemy ])
    assert_equal :flyer_charge, entries.first[:approach_mode]

    MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ flyer ] },
      target_side: { player_id: "p2", combatants: [ enemy ] }
    )

    assert_operator BF.distance_between_units(flyer, enemy), :<=, ENGAGE
  end

  test "far flyer closes distance instead of idling when setup is out of MV" do
    flyer = combatant(
      entity_id: "flyer",
      name: "Костяной дракон",
      x: 8.0,
      y: 12.0,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      melee: 6,
      ranged: 4,
      movement: 5,
      abilities: [ "flying", "monster" ]
    )
    enemy = combatant(
      entity_id: "enemy",
      name: "Стража поляны",
      x: 31.0,
      y: 11.0,
      facing: 180,
      base_width: 5,
      base_depth: 2,
      melee: 2,
      ranged: 5,
      movement: 3,
      side_index: 1
    )

    start_dist = BF.distance_between_units(flyer, enemy)
    assert_operator start_dist, :>, flyer[:movement] + 5

    entries = DecisionsMovement.plan_melee_entries([ flyer ], [ enemy ])
    assert_equal 1, entries.size
    assert_equal :flyer_approach, entries.first[:approach_mode]

    MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ flyer ] },
      target_side: { player_id: "p2", combatants: [ enemy ] }
    )

    end_dist = BF.distance_between_units(flyer, enemy)
    assert_operator end_dist, :<, start_dist - 1.0, "flyer should close toward the enemy"
    assert_operator end_dist, :>=, CONTACT
  end

  test "closing leap prefers leaving an enemy front arc when a safe sample exists" do
    enemy = combatant(
      entity_id: "enemy",
      x: 22.0,
      y: 12.0,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 5,
      movement: 3,
      side_index: 1
    )
    # Just inside the 120° front cone near the upper rim — a short lateral leap can exit.
    flyer = combatant(
      entity_id: "flyer",
      x: 14.0,
      y: 18.5,
      facing: 0,
      base_width: 1,
      base_depth: 1,
      melee: 5,
      movement: 5,
      abilities: [ "flying" ]
    )

    assert BF.in_front_arc?(enemy, flyer, enemy[:facing])
    start_dist = BF.distance_between_units(flyer, enemy)

    entries = DecisionsMovement.plan_melee_entries([ flyer ], [ enemy ])
    assert_equal :flyer_approach, entries.first[:approach_mode]

    MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ flyer ] },
      target_side: { player_id: "p2", combatants: [ enemy ] }
    )

    refute BF.in_front_arc?(enemy, flyer, enemy[:facing]),
      "closing leap should exit the front arc when MV allows"
    assert_operator BF.distance_between_units(flyer, enemy), :<=, start_dist + 0.05
  end

  test "two-turn loop: setup then charge into contact" do
    flyer = combatant(
      entity_id: "flyer",
      x: 8.0,
      y: 12.0,
      facing: 180,
      base_width: 1,
      base_depth: 1,
      melee: 5,
      movement: 8,
      abilities: [ "flying" ]
    )
    enemy = combatant(
      entity_id: "enemy",
      x: 14.0,
      y: 12.0,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )

    refute DecisionsMovement.engaged_with_any?(flyer, [ enemy ])

    MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ flyer ] },
      target_side: { player_id: "p2", combatants: [ enemy ] }
    )

    assert_operator BF.distance_between_units(flyer, enemy), :>=, CONTACT
    assert BF.in_front_arc?(flyer, enemy, flyer[:facing])
    assert_includes %w[rear flank], BF.classify_attack_vector(flyer, enemy)

    MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ flyer ] },
      target_side: { player_id: "p2", combatants: [ enemy ] }
    )

    assert_operator BF.distance_between_units(flyer, enemy), :<=, ENGAGE
  end

  private

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
      attacks: 2
    }.merge(overrides)
  end
end
