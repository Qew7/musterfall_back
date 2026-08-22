require "test_helper"

# Covers the contact-jam fixes: engage snap band, soft charge-target conflicts,
# two-pass contact→flank movement, contact slots, and limited ally flank bypass.
class SimBattleContactChargeTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  CONTACT = Sim::Battle::Pathing::CONTACT
  ENGAGE = Sim::Battle::Pathing::ENGAGE
  MovementPhase = Sim::Battle::Phases::Movement
  DecisionsMovement = Sim::Battle::Decisions::Movement
  GroundMovement = Sim::Battle::Rules::Ground::Movement
  Targeting = Sim::Battle::Decisions::Targeting
  Pathing = Sim::Battle::Pathing

  # ---------------------------------------------------------------------------
  # 1. Contact dead zone / engage band
  # ---------------------------------------------------------------------------

  test "ENGAGE band is CONTACT plus contact_snap" do
    assert_in_delta CONTACT + BF::CONFIG[:contact_snap], ENGAGE, 0.0001
    assert_operator ENGAGE, :>, CONTACT
  end

  test "units microscopically past CONTACT can still choose a melee target" do
    # Centers 3.92 apart with half-depths 2+1.5 → OBB gap 0.42 (dead zone).
    orks = combatant(
      entity_id: "orks",
      name: "Орки-бойзы",
      x: 17.0,
      y: 12.0,
      facing: 0,
      base_width: 4,
      base_depth: 4,
      files: 4,
      ranks: 4,
      melee: 5,
      side_index: 0
    )
    ghouls = combatant(
      entity_id: "ghouls",
      name: "Упырская стая",
      x: 20.92,
      y: 12.0,
      facing: 180,
      base_width: 4,
      base_depth: 3,
      files: 4,
      ranks: 3,
      melee: 4,
      side_index: 1
    )

    gap = BF.distance_between_units(orks, ghouls)
    assert_operator gap, :>, CONTACT
    assert_operator gap, :<=, ENGAGE

    selection = Targeting.choose_target(orks, [ ghouls ], "melee", [ orks, ghouls ])
    assert selection, "expected melee engagement inside ENGAGE band"
    assert_equal "ghouls", selection[:target][:entity_id]
    assert Targeting.in_melee_combat?(orks, [ orks, ghouls ])
  end

  test "approach intent is skipped once inside ENGAGE so units stop micro-creeping" do
    attacker = combatant(
      entity_id: "a1",
      name: "Атакующий",
      x: 10,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      melee: 5,
      movement: 3
    )
    enemy = combatant(
      entity_id: "e1",
      name: "Враг",
      x: 12.3,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 5,
      side_index: 1
    )
    dist = BF.distance_between_units(attacker, enemy)
    assert_operator dist, :<=, ENGAGE

    intent = DecisionsMovement.build_approach_intent(
      combatant: attacker,
      nearest: enemy,
      obstacles: [ enemy ]
    )
    assert_nil intent
  end

  test "a lake beside the tray does not cancel a clear frontal charge" do
    marauders = combatant(
      entity_id: "unit-10",
      name: "Мародеры",
      x: 16.414,
      y: 18.856,
      facing: 346.45,
      base_width: 4,
      base_depth: 4,
      files: 4,
      ranks: 4,
      movement: 3,
      melee: 5
    )
    skeletons = combatant(
      entity_id: "unit-5",
      name: "Скелетный блок",
      x: 22.538,
      y: 16.605,
      facing: 127.28,
      base_width: 5,
      base_depth: 4,
      files: 5,
      ranks: 4,
      melee: 4,
      side_index: 1
    )
    lake = {
      id: "terrain-3",
      type: "lake",
      x: 14.98,
      y: 13.913,
      width: 3.692,
      depth: 3.744,
      impassable: true
    }
    lake_fp = BF.feature_footprint(lake)
    dest = BF.charge_destination(marauders, skeletons)
    assert BF.rectangles_overlap?(marauders.merge(dest), lake_fp), "setup: naive dest nicks the side lake"
    refute BF.line_intersects_feature?(marauders, skeletons, lake), "setup: lake is not between the trays"

    world = Pathing::Obstacles.around(marauders, units: [ marauders, skeletons ], terrain: [ lake ])
    plan = Pathing.plan_approach(
      origin: marauders,
      goal_point: dest,
      budget: 3.0,
      obstacles: world,
      contact_id: skeletons[:entity_id],
      goal_unit: skeletons,
      terrain: [ lake ]
    )
    landed = marauders.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
    refute BF.rectangles_overlap?(landed, lake_fp)
    assert_operator BF.distance_between_units(landed, skeletons), :<=, ENGAGE
  end

  # ---------------------------------------------------------------------------
  # 2. Soft charge-target in conflict resolution
  # ---------------------------------------------------------------------------

  test "charge destination against the target is not treated as a hard footprint conflict" do
    attacker = combatant(
      entity_id: "hero",
      name: "Варбосс",
      x: 10,
      y: 12,
      facing: 0,
      base_width: 1,
      base_depth: 1,
      melee: 6,
      movement: 3
    )
    enemy = combatant(
      entity_id: "target",
      name: "Упыри",
      x: 14,
      y: 12,
      facing: 180,
      base_width: 4,
      base_depth: 3,
      melee: 4,
      side_index: 1
    )
    charge = BF.charge_destination(attacker, enemy)
    pose = attacker.merge(charge)
    dist = BF.distance_between_units(pose, enemy)

    assert_operator dist, :<, CONTACT
    refute MovementPhase.footprints_conflict?(pose, enemy, contact_id: enemy[:entity_id]),
           "charge landing must be soft against its own target"
    assert MovementPhase.footprints_conflict?(pose, enemy, contact_id: nil),
           "without contact_id the same pose still conflicts"
  end

  test "resolve_destination_conflicts keeps a solo charge landing in the contact band" do
    attacker = combatant(
      entity_id: "hero",
      name: "Варбосс",
      x: 10,
      y: 12,
      facing: 0,
      base_width: 1,
      base_depth: 1,
      melee: 6,
      movement: 4,
      initiative: 5
    )
    enemy = combatant(
      entity_id: "target",
      name: "Упыри",
      x: 13.2,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )

    intent = DecisionsMovement.build_approach_intent(
      combatant: attacker,
      nearest: enemy,
      obstacles: [ enemy ]
    )
    assert intent, "expected an approach intent"
    assert intent[:destination]

    packed = intent.merge(
      from: attacker.slice(:x, :y, :facing),
      before: {},
      origin_pose: attacker.dup,
      contact_slot: "front"
    )
    MovementPhase.resolve_destination_conflicts!([ packed ], [ MovementPhase.freeze_obstacle(enemy) ])

    refute packed[:wait], "solo charger must not be waited off its own target"
    assert packed[:destination]
    landed = attacker.merge(packed[:destination])
    assert_operator BF.distance_between_units(landed, enemy), :<=, ENGAGE
    refute BF.rectangles_overlap?(landed, enemy)
  end

  # ---------------------------------------------------------------------------
  # 3. Two-pass movement (contact then flank)
  # ---------------------------------------------------------------------------

  test "flank claimer paths on the board after the front claimer has settled" do
    front = combatant(
      entity_id: "orks",
      name: "Орки-бойзы",
      x: 12,
      y: 12,
      facing: 0,
      base_width: 4,
      base_depth: 4,
      files: 4,
      ranks: 4,
      melee: 5,
      movement: 3,
      initiative: 3
    )
    flanker = combatant(
      entity_id: "skel",
      name: "Скелетный блок",
      x: 16,
      y: 6,
      facing: 135,
      base_width: 5,
      base_depth: 3,
      files: 5,
      ranks: 3,
      melee: 4,
      movement: 3,
      initiative: 2,
      side_index: 0
    )
    # Shared enemy ahead of the orks; skeletons sit on the geometric flank.
    enemy = combatant(
      entity_id: "warboss",
      name: "Варбосс",
      x: 18,
      y: 12,
      facing: 180,
      base_width: 1,
      base_depth: 1,
      melee: 6,
      movement: 3,
      side_index: 1
    )

    # Put skeletons clearly on the warboss flank geometrically.
    flanker[:x] = 20
    flanker[:y] = 7
    flanker[:facing] = 120
    assert_equal "flank", BF.classify_attack_vector(flanker, enemy)

    entries = DecisionsMovement.plan_melee_entries([ front, flanker ], [ enemy ])
    by_id = entries.index_by { |entry| entry[:combatant][:entity_id] }
    assert_equal "front", by_id["orks"][:contact_slot]
    assert_equal "flank", by_id["skel"][:contact_slot]
    assert GroundMovement.contact_wave?(by_id["orks"])
    refute GroundMovement.contact_wave?(by_id["skel"])

    before = BF.distance_between_units(flanker, enemy)
    MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ front, flanker ] },
      target_side: { player_id: "p2", combatants: [ enemy ] }
    )
    after = BF.distance_between_units(flanker, enemy)

    assert_operator after, :<, before
    refute BF.rectangles_overlap?(flanker, front)
  end

  test "a distant front claimer is not in the contact wave" do
    actor = combatant(
      entity_id: "front", name: "Алебардисты",
      x: 4, y: 12, facing: 0, movement: 4,
      base_width: 4, base_depth: 4, melee: 4
    )
    enemy = combatant(
      entity_id: "warboss", name: "Варбосс",
      x: 32, y: 12, facing: 180, movement: 4,
      base_width: 4, base_depth: 4, melee: 4, side_index: 1
    )

    refute DecisionsMovement.this_turn_charge?(actor, enemy, enemies: [ enemy ])
    entries = DecisionsMovement.plan_melee_entries([ actor ], [ enemy ])
    assert_equal "front", entries.first[:contact_slot]
    refute GroundMovement.contact_wave?(entries.first)
  end

  test "this-turn charge spends double MV and can close a gap past 1× movement" do
    attacker = combatant(
      entity_id: "a1", name: "Копейщики",
      x: 10, y: 12, facing: 0, movement: 4,
      base_width: 2, base_depth: 2, melee: 5
    )
    enemy = combatant(
      entity_id: "e1", name: "Мечники",
      x: 18, y: 12, facing: 180, movement: 4,
      base_width: 2, base_depth: 2, melee: 4, side_index: 1
    )

    gap = BF.distance_between_units(attacker, enemy)
    assert_operator gap, :>, attacker[:movement] + ENGAGE
    refute DecisionsMovement.this_turn_charge?(attacker, enemy, enemies: [ enemy ])
    assert DecisionsMovement.within_charge_range?(attacker, enemy, enemies: [ enemy ])

    phase = MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ attacker ] },
      target_side: { player_id: "p2", combatants: [ enemy ] }
    )
    action = phase[:actions].find { |row| row[:actor_id] == "a1" }

    assert action
    assert_in_delta 8.0, action.dig(:maneuver, :mv_budget), 0.001
    assert_in_delta 0.0, action.dig(:maneuver, :mv_spent_march).to_f, 0.05
    assert_operator BF.distance_between_units(attacker, enemy), :<=, ENGAGE
  end

  test "orbit_mode? is ground wrap, not flyer setup" do
    refute GroundMovement.orbit_mode?(:flyer_setup_rear)
    refute GroundMovement.orbit_mode?(:flyer_setup_flank)
    refute GroundMovement.orbit_mode?(:flyer_approach)
    assert GroundMovement.orbit_mode?(:orbit_flank)
    assert GroundMovement.orbit_mode?(:wrap_rear)
  end

  test "flyer wave runs before infantry contact" do
    flyer = combatant(
      entity_id: "hero-1", name: "Принц",
      x: 10, y: 18, facing: 0, movement: 10,
      base_width: 1, base_depth: 2, melee: 6, abilities: [ "flying" ]
    )
    infantry = combatant(
      entity_id: "unit-1", name: "Орки",
      x: 10, y: 12, facing: 0, movement: 4,
      base_width: 4, base_depth: 4, melee: 4
    )
    enemy = combatant(
      entity_id: "warboss", name: "Варбосс",
      x: 16, y: 12, facing: 180, movement: 3,
      base_width: 1, base_depth: 1, melee: 6, side_index: 1
    )

    waves = DecisionsMovement.plan_melee_waves([ flyer, infantry ], [ enemy ])
    assert_equal "hero-1", waves.first[:entries].first[:combatant][:entity_id]
    assert waves.first[:allow_ally_bypass]
    refute waves.dig(1, :allow_ally_bypass)
  end

  test "a second front claimer keeps the nearest enemy on a free slot" do
    prince = combatant(
      entity_id: "hero-3", name: "Демонический принц",
      x: 27.47, y: 0.0, facing: 68.4,
      base_width: 1, base_depth: 2, files: 1, ranks: 1,
      movement: 20, abilities: [ "flying" ], side_index: 1
    )
    marauders = combatant(
      entity_id: "unit-14", name: "Мародеры",
      x: 10.33, y: 4.21, facing: 2.9,
      base_width: 4, base_depth: 4, files: 4, ranks: 4,
      movement: 3, side_index: 1
    )
    halb = combatant(
      entity_id: "unit-18", name: "Алебардисты",
      x: 35.05, y: 6.61, facing: 273.2,
      base_width: 4, base_depth: 4, files: 4, ranks: 4,
      movement: 3, side_index: 0
    )
    swords = combatant(
      entity_id: "unit-16", name: "Имперские мечники",
      x: 30.6, y: 3.09, facing: 182.3,
      base_width: 4, base_depth: 4, files: 4, ranks: 4,
      movement: 3, side_index: 0
    )

    entries = DecisionsMovement.plan_melee_entries([ halb, swords ], [ prince, marauders ])
    by_id = entries.index_by { |entry| entry[:combatant][:entity_id] }

    assert_equal "hero-3", by_id["unit-18"][:nearest][:entity_id]
    assert_equal "hero-3", by_id["unit-16"][:nearest][:entity_id]
    refute_equal by_id["unit-18"][:contact_slot], by_id["unit-16"][:contact_slot]
  end

  test "infantry does not spend the turn wrapping a flyer who is leaping away" do
    flyer = combatant(
      entity_id: "hero-2", name: "Демонический принц",
      x: 31.0, y: 19.0, facing: 180.0,
      base_width: 1, base_depth: 2, files: 1, ranks: 1,
      movement: 20, abilities: [ "flying" ], melee: 6, side_index: 0
    )
    marauders = combatant(
      entity_id: "unit-11", name: "Мародеры",
      x: 35.0, y: 19.0, facing: 180.0,
      base_width: 4, base_depth: 4, files: 4, ranks: 4,
      movement: 3, melee: 4, side_index: 0
    )
    swords = combatant(
      entity_id: "unit-34", name: "Имперские мечники",
      x: 8.0, y: 20.0, facing: 0.0,
      base_width: 4, base_depth: 4, files: 4, ranks: 4,
      melee: 4, side_index: 1
    )

    MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ flyer, marauders ] },
      target_side: { player_id: "p2", combatants: [ swords ] }
    )

    assert_operator marauders[:x], :<, 33.0
  end

  test "a flyer sets up behind when the landing fits even if a frontal charge also fits" do
    flyer = combatant(
      entity_id: "flyer",
      name: "Демонический принц",
      x: 8.0,
      y: 12.0,
      facing: 0.0,
      base_width: 1,
      base_depth: 2,
      files: 1,
      ranks: 1,
      movement: 20,
      abilities: [ "flying" ],
      melee: 6,
      side_index: 0
    )
    enemy = combatant(
      entity_id: "block",
      name: "Имперские мечники",
      x: 20.0,
      y: 12.0,
      facing: 180.0,
      base_width: 4,
      base_depth: 4,
      files: 4,
      ranks: 4,
      melee: 4,
      side_index: 1
    )

    assert_equal "front", BF.classify_attack_vector(flyer, enemy)
    assert DecisionsMovement.this_turn_charge?(flyer, enemy, enemies: [ enemy ])

    entries = DecisionsMovement.plan_melee_entries([ flyer ], [ enemy ])
    assert_equal 1, entries.size
    assert_includes %i[flyer_setup_rear flyer_setup_flank], entries.first[:approach_mode]
    assert_includes %w[rear flank], entries.first[:contact_slot]
  end

  test "a flyer charges a free side when it cannot land behind this turn" do
    flyer = combatant(
      entity_id: "flyer",
      name: "Демонический принц",
      x: 10.0,
      y: 12.0,
      facing: 0.0,
      base_width: 1,
      base_depth: 2,
      files: 1,
      ranks: 1,
      movement: 6,
      abilities: [ "flying" ],
      melee: 6,
      side_index: 0
    )
    enemy = combatant(
      entity_id: "block",
      name: "Имперские мечники",
      x: 16.0,
      y: 12.0,
      facing: 180.0,
      base_width: 4,
      base_depth: 4,
      files: 4,
      ranks: 4,
      melee: 4,
      side_index: 1
    )

    assert DecisionsMovement.this_turn_charge?(flyer, enemy, enemies: [ enemy ])
    refute Sim::Battle::Rules::Flying::Movement.setup_goal_within_budget?(flyer, enemy, "rear", 6)
    refute Sim::Battle::Rules::Flying::Movement.setup_goal_within_budget?(flyer, enemy, "flank", 6)

    entries = DecisionsMovement.plan_melee_entries([ flyer ], [ enemy ])
    assert_equal 1, entries.size
    assert_equal :flyer_charge, entries.first[:approach_mode]
    assert_equal "front", entries.first[:contact_slot]
  end

  test "a flyer already on the rear charges instead of leaping to another setup" do
    flyer = combatant(
      entity_id: "flyer",
      name: "Демонический принц",
      x: 24.0,
      y: 12.0,
      facing: 180.0,
      base_width: 1,
      base_depth: 2,
      files: 1,
      ranks: 1,
      movement: 20,
      abilities: [ "flying" ],
      melee: 6,
      side_index: 0
    )
    enemy = combatant(
      entity_id: "block",
      name: "Имперские мечники",
      x: 20.0,
      y: 12.0,
      facing: 180.0,
      base_width: 4,
      base_depth: 4,
      files: 4,
      ranks: 4,
      melee: 4,
      side_index: 1
    )

    assert_equal "rear", BF.classify_attack_vector(flyer, enemy)
    assert DecisionsMovement.this_turn_charge?(flyer, enemy, enemies: [ enemy ])

    entries = DecisionsMovement.plan_melee_entries([ flyer ], [ enemy ])
    assert_equal 1, entries.size
    assert_equal :flyer_charge, entries.first[:approach_mode]
    assert_equal "rear", entries.first[:contact_slot]
  end

  test "a flyer takes the free flank when a rear pad faces into a packed neighbor" do
    flyer = combatant(
      entity_id: "unit-88",
      name: "Костяной дракон",
      x: 8.77,
      y: 4.34,
      facing: 271.8,
      base_width: 2,
      base_depth: 2,
      files: 1,
      ranks: 1,
      movement: 20,
      abilities: [ "flying" ],
      melee: 6,
      side_index: 0
    )
    target = combatant(
      entity_id: "unit-61",
      name: "Труповозка",
      x: 2.0,
      y: 15.0,
      facing: 0.0,
      base_width: 2,
      base_depth: 2,
      files: 2,
      ranks: 1,
      melee: 3,
      side_index: 1
    )
    neighbor = combatant(
      entity_id: "unit-86",
      name: "Труповозка",
      x: 1.0,
      y: 11.0,
      facing: 0.0,
      base_width: 2,
      base_depth: 1,
      files: 2,
      ranks: 1,
      melee: 3,
      side_index: 1
    )
    enemies = [ target, neighbor ]

    entries = DecisionsMovement.plan_melee_entries([ flyer ], enemies)
    assert_equal 1, entries.size
    assert_equal :flyer_setup_flank, entries.first[:approach_mode]
    assert_equal "flank", entries.first[:contact_slot]
    assert_equal "unit-61", entries.first[:nearest][:entity_id]

    phase = MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ flyer ] },
      target_side: { player_id: "p2", combatants: enemies }
    )
    leap = phase[:actions].find do |action|
      action[:type] == "movement" && action[:actor_id] == "unit-88" &&
        action.dig(:maneuver, :kind) != "row_advance"
    end
    refute_nil leap
    refute_equal "blocked_by_ally", leap.dig(:maneuver, :kind)
    assert_operator BF.distance_between(leap[:from], leap[:to]), :>, 0.05
    assert_operator BF.distance_between_units(flyer, neighbor), :>=, CONTACT
  end

  test "this-turn charge takes the closer enemy free side over a far routing target" do
    actor = combatant(
      entity_id: "unit-1", x: 24.0, y: 12.0, facing: 180.0,
      base_width: 2, base_depth: 2, movement: 5, melee: 5
    )
    blocker = combatant(
      entity_id: "blocker", name: "Blocker", x: 18.0, y: 12.0, facing: 0.0,
      base_width: 2, base_depth: 2, melee: 4, side_index: 1
    )
    runner = combatant(
      entity_id: "unit-2", name: "Беглец", x: 10.0, y: 12.0, facing: 0.0,
      base_width: 2, base_depth: 2, melee: 4, is_routing: true, side_index: 1
    )

    assert DecisionsMovement.this_turn_charge?(actor, blocker, enemies: [ blocker, runner ])
    refute DecisionsMovement.this_turn_charge?(actor, runner, enemies: [ blocker, runner ])

    entries = DecisionsMovement.plan_melee_entries([ actor ], [ blocker, runner ])
    assert_equal "blocker", entries.first[:nearest][:entity_id]
    assert entries.first[:chargeable]
  end

  # ---------------------------------------------------------------------------
  # 4. Contact slots
  # ---------------------------------------------------------------------------

  test "assign_contact_slots gives front to the most frontal unit and flank to the rest" do
    enemy = combatant(
      entity_id: "e1",
      name: "Цель",
      x: 20,
      y: 12,
      facing: 180,
      base_width: 3,
      base_depth: 3,
      side_index: 1
    )
    frontal = combatant(
      entity_id: "front",
      name: "Фронт",
      x: 12,
      y: 12,
      facing: 0,
      base_width: 4,
      base_depth: 4,
      melee: 5
    )
    side = combatant(
      entity_id: "side",
      name: "Фланг",
      x: 18,
      y: 6,
      facing: 90,
      base_width: 2,
      base_depth: 2,
      melee: 5
    )

    entries = DecisionsMovement.plan_melee_entries([ frontal, side ], [ enemy ])
    slots = entries.to_h { |entry| [ entry[:combatant][:entity_id], entry[:contact_slot] ] }
    assert_equal "front", slots["front"]
    assert_equal "flank", slots["side"]
  end

  test "second claimer on the rear of the target gets the rear slot" do
    enemy = combatant(
      entity_id: "e1",
      name: "Цель",
      x: 20,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      side_index: 1
    )
    front = combatant(
      entity_id: "f1",
      name: "Спереди",
      x: 24,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 5
    )
    rear = combatant(
      entity_id: "r1",
      name: "Сзади",
      x: 14,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      melee: 5
    )

    assert_equal "front", BF.classify_attack_vector(front, enemy)
    assert_equal "rear", BF.classify_attack_vector(rear, enemy)

    entries = DecisionsMovement.plan_melee_entries([ front, rear ], [ enemy ])
    slots = entries.to_h { |entry| [ entry[:combatant][:entity_id], entry[:contact_slot] ] }
    assert_equal "front", slots["f1"]
    assert_equal "rear", slots["r1"]
  end

  test "approach_goal_point for direct flank aims at charge_destination, not a slot waypoint" do
    origin = combatant(entity_id: "a", x: 14, y: 6, facing: 90, base_width: 1, base_depth: 1)
    defender = combatant(entity_id: "d", x: 14, y: 12, facing: 180, base_width: 4, base_depth: 3, side_index: 1)
    assert_equal "flank", BF.classify_attack_vector(origin, defender)
    assert BF.in_front_arc?(origin, defender, origin[:facing])
    goal = GroundMovement.approach_goal_point(origin, defender, contact_slot: "flank", approach_mode: :direct)
    expected = BF.charge_destination(origin, defender)
    assert_in_delta expected[:x], goal[:x], 0.01
    assert_in_delta expected[:y], goal[:y], 0.01
  end

  test "approach_goal_point returns a rear waypoint for wrap_rear" do
    origin = combatant(entity_id: "a", x: 10, y: 12, facing: 0, base_width: 1, base_depth: 1)
    defender = combatant(entity_id: "d", x: 16, y: 12, facing: 180, base_width: 4, base_depth: 3, side_index: 1)
    point = GroundMovement.approach_goal_point(origin, defender, contact_slot: "rear", approach_mode: :wrap_rear)

    refute_equal defender, point
    assert_operator point[:x], :>, defender[:x]
  end

  test "approach_goal_point for a frontal assignment under direct mode aims at charge_destination" do
    origin = combatant(entity_id: "a", x: 10, y: 12, facing: 0, base_width: 1, base_depth: 1)
    defender = combatant(entity_id: "d", x: 14, y: 12, facing: 180, base_width: 4, base_depth: 3, side_index: 1)
    assert_equal "front", BF.classify_attack_vector(origin, defender)
    goal = GroundMovement.approach_goal_point(origin, defender, contact_slot: "flank", approach_mode: :direct)
    expected = BF.charge_destination(origin, defender)
    assert_in_delta expected[:x], goal[:x], 0.01
    assert_in_delta expected[:y], goal[:y], 0.01
  end

  test "approach_goal_point steps along facing when already in the fight" do
    origin = combatant(entity_id: "a", x: 12, y: 12, facing: 0, base_width: 4, base_depth: 4)
    defender = combatant(entity_id: "d", x: 16.5, y: 12, facing: 180, base_width: 4, base_depth: 4, side_index: 1)
    gap = BF.distance_between_units(origin, defender)
    assert_operator gap, :<=, 1.0
    goal = GroundMovement.approach_goal_point(origin, defender, contact_slot: "front", approach_mode: :direct)
    stepped = BF.move_along_facing(origin, [ gap, 0.5 ].min)
    assert_in_delta stepped[:x], goal[:x], 0.01
    assert_in_delta stepped[:y], goal[:y], 0.01
  end

  test "approach_goal_point for orbit_flank leaves the defender center" do
    origin = combatant(entity_id: "a", x: 10, y: 12, facing: 0, base_width: 1, base_depth: 1)
    defender = combatant(entity_id: "d", x: 16, y: 12, facing: 180, base_width: 4, base_depth: 3, side_index: 1)
    goal = GroundMovement.approach_goal_point(origin, defender, contact_slot: "flank", approach_mode: :orbit_flank)

    refute_equal defender, goal
    assert_operator BF.distance_between(goal, defender), :>, 1.0
  end

  # ---------------------------------------------------------------------------
  # 5. Limited ally bypass for flank / rear / small footprint
  # ---------------------------------------------------------------------------

  test "frontal approach wraps an allied blocker instead of waiting" do
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

    assert_equal "front", BF.classify_attack_vector(origin, enemy)
    plan = Pathing.plan_approach(
      origin: origin,
      goal_point: enemy,
      budget: 5,
      obstacles: [ ally, enemy ],
      contact_id: enemy[:entity_id],
      goal_unit: enemy
    )

    assert plan[:pose]
    refute plan[:blocked_by_ally]
    assert plan[:avoided]
    traveled = BF.distance_between(origin, plan[:pose])
    assert_operator traveled, :>, 0.2
    landed = origin.merge(plan[:pose])
    refute BF.rectangles_overlap?(landed, ally)
    refute BF.rectangles_overlap?(landed, enemy)
  end

  test "geometric flank approach may bypass an allied blocker" do
    # Enemy faces west; hero sits due south (true flank). Ally sits on the northbound line.
    origin = combatant(
      entity_id: "hero",
      name: "Варбосс",
      x: 18,
      y: 6,
      facing: 90,
      base_width: 1,
      base_depth: 1,
      movement: 5,
      melee: 6,
      side_index: 0
    )
    ally = combatant(
      entity_id: "boyz",
      name: "Орки-бойзы",
      x: 18,
      y: 9.5,
      facing: 0,
      base_width: 4,
      base_depth: 4,
      melee: 5,
      side_index: 0
    )
    enemy = combatant(
      entity_id: "ghouls",
      name: "Упырская стая",
      x: 18,
      y: 14,
      facing: 180,
      base_width: 4,
      base_depth: 3,
      melee: 4,
      side_index: 1
    )

    assert_equal "flank", BF.classify_attack_vector(origin, enemy)
    plan = Pathing.plan_approach(
      origin: origin,
      goal_point: enemy,
      budget: 5,
      obstacles: [ ally, enemy ],
      contact_id: enemy[:entity_id],
      goal_unit: enemy,
      allow_ally_bypass: true
    )

    assert plan[:pose]
    refute plan[:blocked_by_ally]
    traveled = BF.distance_between(origin, plan[:pose])
    assert_operator traveled, :>, 0.2
    landed = origin.merge(plan[:pose])
    refute BF.rectangles_overlap?(landed, ally)
  end

  test "small footprint wraps an ally on a frontal line" do
    origin = combatant(
      entity_id: "hero",
      name: "Герой",
      x: 8,
      y: 12,
      facing: 0,
      base_width: 1,
      base_depth: 1,
      movement: 6,
      melee: 6,
      side_index: 0
    )
    ally = combatant(
      entity_id: "block",
      name: "Блок",
      x: 12,
      y: 12,
      facing: 0,
      base_width: 4,
      base_depth: 4,
      side_index: 0
    )
    enemy = combatant(
      entity_id: "e1",
      name: "Враг",
      x: 20,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      side_index: 1
    )

    plan = Pathing.plan_approach(
      origin: origin,
      goal_point: enemy,
      budget: 6,
      obstacles: [ ally, enemy ],
      contact_id: enemy[:entity_id],
      goal_unit: enemy,
      allow_ally_bypass: true
    )

    assert plan[:pose]
    refute plan[:blocked_by_ally]
    assert plan[:avoided]
    traveled = BF.distance_between(origin, plan[:pose])
    assert_operator traveled, :>, 0.2
    landed = origin.merge(plan[:pose])
    refute BF.rectangles_overlap?(landed, ally)
  end

  # ---------------------------------------------------------------------------
  # Integration: battle-243 style jam
  # ---------------------------------------------------------------------------

  test "battle jam: almost-touching orks and ghouls engage instead of deadlocking" do
    orks = combatant(
      entity_id: "unit-9",
      name: "Орки-бойзы",
      x: 17.019824912779473,
      y: 11.662088699237485,
      facing: 356.6571949365198,
      base_width: 4,
      base_depth: 4,
      files: 4,
      ranks: 4,
      melee: 5,
      movement: 3,
      side_index: 0
    )
    warboss = combatant(
      entity_id: "hero-3",
      name: "Варбосс",
      x: 18.245861319604572,
      y: 8.459794183657628,
      facing: 47.794468274607084,
      base_width: 1,
      base_depth: 1,
      melee: 6,
      movement: 3,
      initiative: 5,
      side_index: 0
    )
    ghouls = combatant(
      entity_id: "unit-13",
      name: "Упырская стая",
      x: 20.913959326907648,
      y: 11.434326219959171,
      facing: 176.67250579468623,
      base_width: 4,
      base_depth: 3,
      files: 4,
      ranks: 3,
      melee: 4,
      movement: 3,
      side_index: 1
    )
    skel = combatant(
      entity_id: "unit-14",
      name: "Скелетный блок",
      x: 22.7718364727,
      y: 5.1706886416,
      facing: 144.935284,
      base_width: 5,
      base_depth: 4,
      files: 5,
      ranks: 4,
      melee: 3,
      movement: 3,
      side_index: 1
    )

    gap = BF.distance_between_units(orks, ghouls)
    assert_operator gap, :>=, CONTACT
    assert_operator gap, :<=, ENGAGE

    # Greenskin turn: orks should be considered engaged (no futile creep).
    intent = DecisionsMovement.build_approach_intent(
      combatant: orks,
      nearest: ghouls,
      obstacles: [ warboss, ghouls, skel ]
    )
    assert_nil intent

    selection = Targeting.choose_target(orks, [ ghouls, skel ], "melee", [ orks, warboss, ghouls, skel ])
    assert selection
    assert_equal "unit-13", selection[:target][:entity_id]
  end

  test "battle jam: skeleton on the warboss flank reaches melee" do
    warboss = combatant(
      entity_id: "hero-3",
      name: "Варбосс",
      x: 18.25,
      y: 8.46,
      facing: 48,
      base_width: 1,
      base_depth: 1,
      melee: 6,
      movement: 3,
      side_index: 0
    )
    orks = combatant(
      entity_id: "unit-9",
      name: "Орки-бойзы",
      x: 17.02,
      y: 11.66,
      facing: 357,
      base_width: 4,
      base_depth: 4,
      files: 4,
      ranks: 4,
      melee: 5,
      movement: 3,
      side_index: 0
    )
    ghouls = combatant(
      entity_id: "unit-13",
      name: "Упырская стая",
      x: 20.91,
      y: 11.43,
      facing: 177,
      base_width: 4,
      base_depth: 3,
      files: 4,
      ranks: 3,
      melee: 4,
      movement: 3,
      side_index: 1
    )
    ghouls_rear = combatant(
      entity_id: "unit-16",
      name: "Упырская стая",
      x: 24.43,
      y: 11.37,
      facing: 178,
      base_width: 4,
      base_depth: 3,
      files: 4,
      ranks: 3,
      melee: 4,
      movement: 3,
      side_index: 1
    )
    skel = combatant(
      entity_id: "unit-14",
      name: "Скелетный блок",
      x: 22.77,
      y: 5.17,
      facing: 145,
      base_width: 5,
      base_depth: 3,
      files: 5,
      ranks: 3,
      melee: 3,
      movement: 3,
      side_index: 1
    )

    assert_equal "flank", BF.classify_attack_vector(skel, warboss)
    before = BF.distance_between_units(skel, warboss)

    4.times do
      MovementPhase.play(
        acting_side: { player_id: "undead", combatants: [ ghouls, ghouls_rear, skel ] },
        target_side: { player_id: "greenskin", combatants: [ warboss, orks ] }
      )
      break if Targeting.choose_target(skel, [ warboss, orks ], "melee", [ warboss, orks, ghouls, ghouls_rear, skel ])
    end

    after = BF.distance_between_units(skel, warboss)
    assert_operator after, :<, before
    assert_operator after, :<, 1.0, "skeleton flank charge should close (before=#{before.round(3)} after=#{after.round(3)})"
    refute BF.rectangles_overlap?(skel, ghouls)
    refute BF.rectangles_overlap?(skel, ghouls_rear)
  end

  test "battle jam: warboss can progress toward ghouls without being erased by ork conflict" do
    warboss = combatant(
      entity_id: "hero-3",
      name: "Варбосс",
      x: 18.0846888466,
      y: 8.3146809393,
      facing: 46.174128,
      base_width: 1,
      base_depth: 1,
      melee: 6,
      movement: 3,
      initiative: 5,
      side_index: 0
    )
    orks = combatant(
      entity_id: "unit-9",
      name: "Орки-бойзы",
      x: 17.0151976497,
      y: 11.6620499371,
      facing: 356.744795,
      base_width: 4,
      base_depth: 4,
      files: 4,
      ranks: 4,
      melee: 5,
      movement: 3,
      initiative: 3,
      side_index: 0
    )
    ghouls = combatant(
      entity_id: "unit-13",
      name: "Упырская стая",
      x: 20.9139593269,
      y: 11.4343262200,
      facing: 176.672506,
      base_width: 4,
      base_depth: 3,
      files: 4,
      ranks: 3,
      melee: 4,
      side_index: 1
    )

    before_wb = BF.distance_between_units(warboss, ghouls)
    before_orks = BF.distance_between_units(orks, ghouls)

    MovementPhase.play(
      acting_side: { player_id: "greenskin", combatants: [ warboss, orks ] },
      target_side: { player_id: "undead", combatants: [ ghouls ] }
    )

    # Orks in the ENGAGE band should stay put (already fighting).
    if before_orks <= ENGAGE
      assert_in_delta before_orks, BF.distance_between_units(orks, ghouls), 0.05
      assert Targeting.choose_target(orks, [ ghouls ], "melee", [ warboss, orks, ghouls ])
    end

    after_wb = BF.distance_between_units(warboss, ghouls)
    # Soft target + slots: warboss must not be waited off; either engages or closes.
    assert(
      after_wb <= ENGAGE || after_wb < before_wb - 0.08,
      "warboss should close meaningfully (before=#{before_wb.round(3)} after=#{after_wb.round(3)})"
    )
    refute BF.rectangles_overlap?(warboss, orks)
    assert_operator BF.distance_between_units(warboss, orks), :>=, CONTACT - 0.001
  end

  test "contact_slot_points returns side waypoints for flank and a rear point for rear" do
    origin = combatant(entity_id: "a", x: 10, y: 12, base_width: 1, base_depth: 1)
    defender = combatant(entity_id: "d", x: 16, y: 12, facing: 180, base_width: 4, base_depth: 3)

    flanks = Pathing.contact_slot_points(origin, defender, "flank")
    assert_equal 2, flanks.size
    assert flanks.all? { |point| (point[:y] - defender[:y]).abs > 1.0 }

    rears = Pathing.contact_slot_points(origin, defender, "rear")
    assert_equal 1, rears.size
    # Defender faces 180 (−x), so rear is toward +x.
    assert_operator rears.first[:x], :>, defender[:x]
  end

  # ---------------------------------------------------------------------------
  # 7. Front-arc assaults, claimed sides, corner contact + free align
  # ---------------------------------------------------------------------------

  test "enemy outside the front arc is ignored by nearest_enemy but is charged if MV reaches a free side" do
    attacker = combatant(
      entity_id: "a1",
      name: "Нападающий",
      x: 10,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      movement: 5,
      melee: 5
    )
    enemy = combatant(
      entity_id: "e1",
      name: "Вне арки",
      x: 10,
      y: 18,
      facing: 270,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )

    refute BF.in_front_arc?(attacker, enemy, attacker[:facing])
    assert_nil DecisionsMovement.nearest_enemy(attacker, [ enemy ])
    assert DecisionsMovement.this_turn_charge?(attacker, enemy, enemies: [ enemy ])

    entries = DecisionsMovement.plan_melee_entries([ attacker ], [ enemy ])
    assert_equal 1, entries.size
    assert_equal BF.classify_attack_vector(attacker, enemy), entries.first[:contact_slot]
    assert_equal :direct, entries.first[:approach_mode]
    assert entries.first[:chargeable]
  end

  test "second claimer on a taken front retargets another in-arc enemy" do
    enemy_a = combatant(
      entity_id: "ea",
      name: "Цель A",
      x: 18,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )
    enemy_b = combatant(
      entity_id: "eb",
      name: "Цель B",
      x: 18,
      y: 8,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )
    first = combatant(
      entity_id: "u1",
      name: "Первый",
      x: 10,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      movement: 3,
      melee: 5
    )
    second = combatant(
      entity_id: "u2",
      name: "Второй",
      x: 10,
      y: 11.5,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      movement: 3,
      melee: 5
    )

    assert BF.in_front_arc?(first, enemy_a, first[:facing])
    assert BF.in_front_arc?(second, enemy_a, second[:facing])
    assert BF.in_front_arc?(second, enemy_b, second[:facing])

    entries = DecisionsMovement.plan_melee_entries([ first, second ], [ enemy_a, enemy_b ])
    by_id = entries.index_by { |entry| entry[:combatant][:entity_id] }

    assert_equal "ea", by_id["u1"][:nearest][:entity_id]
    assert_equal "front", by_id["u1"][:contact_slot]
    assert_equal :direct, by_id["u1"][:approach_mode]
    assert_equal "eb", by_id["u2"][:nearest][:entity_id]
    assert_equal :direct, by_id["u2"][:approach_mode]
  end

  test "when front is taken and no other enemy exists claimer orbits free flank" do
    enemy = combatant(
      entity_id: "e1",
      name: "Одинокая цель",
      x: 18,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )
    first = combatant(
      entity_id: "u1",
      name: "Фронт",
      x: 10,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      movement: 3,
      melee: 5
    )
    second = combatant(
      entity_id: "u2",
      name: "Второй",
      x: 10,
      y: 13,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      movement: 3,
      melee: 5
    )

    entries = DecisionsMovement.plan_melee_entries([ first, second ], [ enemy ])
    by_id = entries.index_by { |entry| entry[:combatant][:entity_id] }

    assert_equal "front", by_id["u1"][:contact_slot]
    assert_equal :direct, by_id["u1"][:approach_mode]
    assert_equal "flank", by_id["u2"][:contact_slot]
    assert_equal :orbit_flank, by_id["u2"][:approach_mode]
  end

  test "when front and flank are taken claimer wraps free rear" do
    enemy = combatant(
      entity_id: "e1",
      name: "Цель",
      x: 18,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )
    front = combatant(entity_id: "f1", name: "Фронт", x: 12, y: 12, facing: 0, base_width: 2, base_depth: 2, movement: 3, melee: 5)
    flank = combatant(entity_id: "k1", name: "Фланг", x: 18, y: 6, facing: 90, base_width: 2, base_depth: 2, movement: 3, melee: 5)
    extra = combatant(entity_id: "x1", name: "Третий", x: 11, y: 12.5, facing: 0, base_width: 2, base_depth: 2, movement: 3, melee: 5)

    assert_equal "front", BF.classify_attack_vector(front, enemy)
    assert_equal "flank", BF.classify_attack_vector(flank, enemy)
    assert BF.in_front_arc?(extra, enemy, extra[:facing])

    entries = DecisionsMovement.plan_melee_entries([ front, flank, extra ], [ enemy ])
    by_id = entries.index_by { |entry| entry[:combatant][:entity_id] }

    assert_equal "front", by_id["f1"][:contact_slot]
    assert_equal "flank", by_id["k1"][:contact_slot]
    assert_equal "rear", by_id["x1"][:contact_slot]
    assert_equal :wrap_rear, by_id["x1"][:approach_mode]
  end

  test "when front and rear are taken the extra unit orbits free flank" do
    enemy = combatant(
      entity_id: "e1",
      name: "Цель",
      x: 18,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )
    front = combatant(entity_id: "f1", name: "Фронт", x: 12, y: 12, facing: 0, base_width: 2, base_depth: 2, movement: 3, melee: 5)
    rear = combatant(entity_id: "r1", name: "Тыл", x: 24, y: 12, facing: 180, base_width: 2, base_depth: 2, movement: 3, melee: 5)
    extra = combatant(entity_id: "x1", name: "Лишний", x: 11, y: 12.5, facing: 0, base_width: 2, base_depth: 2, movement: 3, melee: 5)

    assert_equal "front", BF.classify_attack_vector(front, enemy)
    assert_equal "rear", BF.classify_attack_vector(rear, enemy)
    assert BF.in_front_arc?(extra, enemy, extra[:facing])

    entries = DecisionsMovement.plan_melee_entries([ front, rear, extra ], [ enemy ])
    by_id = entries.index_by { |entry| entry[:combatant][:entity_id] }

    assert_equal "front", by_id["f1"][:contact_slot]
    assert_equal "rear", by_id["r1"][:contact_slot]
    assert_equal "flank", by_id["x1"][:contact_slot]
    assert_equal :orbit_flank, by_id["x1"][:approach_mode]
  end

  test "when all three sides are taken the extra unit does not assault" do
    enemy = combatant(
      entity_id: "e1",
      name: "Цель",
      x: 18,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )
    front = combatant(entity_id: "f1", name: "Фронт", x: 12, y: 12, facing: 0, base_width: 2, base_depth: 2, movement: 3, melee: 5)
    flank = combatant(entity_id: "k1", name: "Фланг", x: 18, y: 6, facing: 90, base_width: 2, base_depth: 2, movement: 3, melee: 5)
    rear = combatant(entity_id: "r1", name: "Тыл", x: 24, y: 12, facing: 180, base_width: 2, base_depth: 2, movement: 3, melee: 5)
    extra = combatant(entity_id: "x1", name: "Лишний", x: 11, y: 12.5, facing: 0, base_width: 2, base_depth: 2, movement: 3, melee: 5)

    entries = DecisionsMovement.plan_melee_entries([ front, flank, rear, extra ], [ enemy ])
    ids = entries.map { |entry| entry[:combatant][:entity_id] }

    assert_includes ids, "f1"
    assert_includes ids, "k1"
    assert_includes ids, "r1"
    refute_includes ids, "x1"
  end

  test "out-of-arc melee within MV charges a free flank this turn" do
    enemy = combatant(
      entity_id: "e1",
      name: "Цель",
      x: 18,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )
    attacker = combatant(
      entity_id: "a1",
      name: "Обходчик",
      x: 18,
      y: 7,
      facing: 270,
      base_width: 2,
      base_depth: 2,
      movement: 4,
      melee: 5
    )

    assert_equal "flank", BF.classify_attack_vector(attacker, enemy)
    refute BF.in_front_arc?(attacker, enemy, attacker[:facing])
    assert DecisionsMovement.this_turn_charge?(attacker, enemy, enemies: [ enemy ])

    entries = DecisionsMovement.plan_melee_entries([ attacker ], [ enemy ])
    assert_equal 1, entries.size
    assert_equal "flank", entries.first[:contact_slot]
    assert_equal :direct, entries.first[:approach_mode]
    assert entries.first[:chargeable]

    before = BF.distance_between_units(attacker, enemy)
    MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ attacker ] },
      target_side: { player_id: "p2", combatants: [ enemy ] }
    )
    assert_operator BF.distance_between_units(attacker, enemy), :<=, before
  end

  test "out-of-arc melee on a side flank reforms toward the enemy" do
    enemy = combatant(
      entity_id: "e1",
      name: "Цель",
      x: 22,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )
    attacker = combatant(
      entity_id: "a1",
      name: "Далеко",
      x: 8,
      y: 4,
      facing: 270,
      base_width: 2,
      base_depth: 2,
      movement: 3,
      melee: 5
    )

    refute BF.in_front_arc?(attacker, enemy, attacker[:facing])
    assert BF.in_flank_arc?(attacker, enemy, attacker[:facing])
    assert_operator BF.distance_between_units(attacker, enemy), :>, attacker[:movement] * 2

    entries = DecisionsMovement.plan_melee_entries([ attacker ], [ enemy ])
    assert_equal 1, entries.size
    assert_equal :direct, entries.first[:approach_mode]
    refute_equal :orbit_flank, entries.first[:approach_mode]

    before = BF.angle_between(attacker[:facing], attacker, enemy)
    MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ attacker ] },
      target_side: { player_id: "p2", combatants: [ enemy ] }
    )
    assert_operator BF.angle_between(attacker[:facing], attacker, enemy), :<, before
  end

  test "a block facing off the fight turns toward a flank-arc enemy" do
    block = combatant(
      entity_id: "unit-22",
      name: "Скелетный блок",
      x: 4.0,
      y: 13.5,
      facing: 90.0,
      base_width: 5,
      base_depth: 4,
      movement: 3,
      melee: 5
    )
    warboss = combatant(
      entity_id: "hero-6",
      name: "Варбосс",
      x: 28.2,
      y: 18.4,
      facing: 196.0,
      base_width: 1,
      base_depth: 1,
      melee: 4,
      side_index: 1
    )

    refute BF.in_front_arc?(block, warboss, block[:facing])
    assert BF.in_flank_arc?(block, warboss, block[:facing])

    entries = DecisionsMovement.plan_melee_entries([ block ], [ warboss ])
    assert_equal 1, entries.size
    assert_equal "hero-6", entries.first[:nearest][:entity_id]
    assert_equal :direct, entries.first[:approach_mode]

    before = BF.angle_between(block[:facing], block, warboss)
    MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ block ] },
      target_side: { player_id: "p2", combatants: [ warboss ] }
    )
    refute_in_delta 90.0, block[:facing], 0.5
    assert_operator BF.angle_between(block[:facing], block, warboss), :<, before
  end

  test "an enemy strictly behind does not pull a flank-arc reform" do
    attacker = combatant(
      entity_id: "a1", x: 20, y: 12, facing: 0,
      base_width: 2, base_depth: 2, movement: 3, melee: 5
    )
    rear = combatant(
      entity_id: "e1", name: "Тыл", x: 8, y: 12, facing: 0,
      base_width: 2, base_depth: 2, melee: 4, side_index: 1
    )

    refute BF.in_front_arc?(attacker, rear, attacker[:facing])
    refute BF.in_flank_arc?(attacker, rear, attacker[:facing])
    assert_empty DecisionsMovement.plan_melee_entries([ attacker ], [ rear ])
  end

  test "engaged melee does not set up on a nearby open flank" do
    enemy = combatant(
      entity_id: "e1",
      name: "В контакте",
      x: 12.4,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )
    other = combatant(
      entity_id: "e2",
      name: "Открытый фланг",
      x: 12.5,
      y: 7,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )
    attacker = combatant(
      entity_id: "a1",
      name: "Занят",
      x: 10,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      movement: 4,
      melee: 5
    )

    assert DecisionsMovement.engaged?(attacker, enemy)
    refute BF.in_front_arc?(attacker, other, attacker[:facing])

    entries = DecisionsMovement.plan_melee_entries([ attacker ], [ enemy, other ])
    # Engaged with e1 → no approach; must not steal e2's flank for a setup move.
    refute entries.any? { |entry| entry[:nearest][:entity_id] == "e2" }
  end

  test "in-arc wide infantry charges directly without burning MV on a flank waypoint" do
    attacker = combatant(
      entity_id: "marauders",
      name: "Мародеры",
      x: 17.0,
      y: 5.9,
      facing: 45.0,
      base_width: 4,
      base_depth: 3,
      files: 4,
      ranks: 3,
      movement: 3,
      melee: 5
    )
    enemy = combatant(
      entity_id: "treeman",
      name: "Древочеловек",
      x: 19.2,
      y: 12.3,
      facing: 150.0,
      base_width: 4,
      base_depth: 2,
      files: 2,
      ranks: 1,
      melee: 6,
      side_index: 1
    )

    assert_equal "flank", BF.classify_attack_vector(attacker, enemy)
    assert BF.in_front_arc?(attacker, enemy, attacker[:facing])

    entries = DecisionsMovement.plan_melee_entries([ attacker ], [ enemy ])
    assert_equal 1, entries.size
    assert_equal :direct, entries.first[:approach_mode]

    before = BF.distance_between_units(attacker, enemy)
    phase = MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ attacker ] },
      target_side: { player_id: "p2", combatants: [ enemy ] }
    )
    after = BF.distance_between_units(attacker, enemy)

    assert_operator after, :<, before
    action = phase[:actions].find { |row| row[:actor_id] == "marauders" }
    assert action
    # Must spend some advance/march toward the enemy, not the entire budget on a flank-orbit wheel.
    forward = action.dig(:maneuver, :mv_spent_advance).to_f + action.dig(:maneuver, :mv_spent_march).to_f
    assert_operator forward, :>, 0.05
    assert_operator action.dig(:maneuver, :mv_spent_wheel).to_f, :<, 3.0
  end

  test "corner_contact_reachable when MV can close the OBB gap" do
    attacker = combatant(
      entity_id: "a1",
      x: 10,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 2,
      movement: 4,
      melee: 5
    )
    enemy = combatant(
      entity_id: "e1",
      x: 14.2,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      melee: 4,
      side_index: 1
    )

    gap = BF.distance_between_units(attacker, enemy)
    assert_operator gap, :>, ENGAGE
    assert_operator gap, :<, 4.0
    assert DecisionsMovement.corner_contact_reachable?(attacker, enemy, 4.0)
    refute DecisionsMovement.corner_contact_reachable?(attacker, enemy, 0.5)
  end

  test "corner contact then free align presses fronts without sliding for max frontage" do
    attacker = combatant(
      entity_id: "a1",
      name: "Нападающий",
      x: 10.0,
      y: 13.5,
      facing: 15.0,
      base_width: 4,
      base_depth: 2,
      files: 4,
      ranks: 2,
      model_width: 1,
      model_depth: 1,
      movement: 5,
      melee: 5,
      attacks: 1
    )
    enemy = combatant(
      entity_id: "e1",
      name: "Цель",
      x: 14.0,
      y: 12.0,
      facing: 180.0,
      base_width: 3,
      base_depth: 2,
      files: 3,
      ranks: 2,
      model_width: 1,
      model_depth: 1,
      melee: 4,
      side_index: 1
    )

    assert BF.in_front_arc?(attacker, enemy, attacker[:facing])
    assert DecisionsMovement.corner_contact_reachable?(attacker, enemy, 5.0)

    phase = MovementPhase.play(
      acting_side: { player_id: "p1", combatants: [ attacker ] },
      target_side: { player_id: "p2", combatants: [ enemy ] }
    )

    assert_operator BF.distance_between_units(attacker, enemy), :<=, ENGAGE
    refute BF.rectangles_overlap?(attacker, enemy)

    action = phase[:actions].find { |row| row[:actor_id] == "a1" }
    assert action
    assert action.dig(:maneuver, :free_align) || BF.distance_between_units(attacker, enemy) <= ENGAGE

    engaged = Sim::Battle::Phases::AttackResolution.engaged_model_count(attacker, enemy)
    assert_operator engaged, :>=, 1
    assert_operator engaged, :<=, attacker[:files]
  end

  test "contact_pivot_point hinges on the enemy corner when it touches our front" do
    attacker = combatant(
      entity_id: "ghouls",
      x: 19.375619542743166,
      y: 17.908125159716665,
      facing: 137.27159254886192,
      base_width: 4,
      base_depth: 3
    )
    defender = combatant(
      entity_id: "knights",
      x: 16.60974683974449,
      y: 21.229943353475544,
      facing: 161.1168639579779,
      base_width: 3,
      base_depth: 4,
      side_index: 1
    )

    assert_operator BF.distance_between_units(attacker, defender), :<=, ENGAGE
    pivot = BF.contact_pivot_point(attacker, defender)
    assert pivot

    # Closest feature is defender rear-right corner on attacker front.
    def_corners = BF.unit_corners(defender)
    rear_right = def_corners[2] # front_left, front_right, rear_right, rear_left
    assert_in_delta rear_right[:x], pivot[:x], 0.05
    assert_in_delta rear_right[:y], pivot[:y], 0.05
  end

  test "free align around enemy corner finishes facing into the contacted face" do
    # Battle 23 paid landing: ghouls' front vs knights' rear corner.
    attacker = combatant(
      entity_id: "ghouls",
      x: 19.375619542743166,
      y: 17.908125159716665,
      facing: 137.27159254886192,
      base_width: 4,
      base_depth: 3,
      files: 4,
      ranks: 3
    )
    defender = combatant(
      entity_id: "knights",
      x: 16.60974683974449,
      y: 21.229943353475544,
      facing: 161.1168639579779,
      base_width: 3,
      base_depth: 4,
      files: 3,
      ranks: 4,
      side_index: 1
    )

    desired = BF.facing_into_contact_face(attacker, defender)
    before_err = BF.shortest_facing_delta(attacker[:facing], desired).abs
    assert_operator before_err, :>, 10

    aligned = BF.align_fronts_pose(attacker, defender)
    after_err = BF.shortest_facing_delta(aligned[:facing], desired).abs

    refute BF.rectangles_overlap?(aligned, defender)
    assert_operator BF.distance_between_units(aligned, defender), :<=, ENGAGE
    assert_operator after_err, :<, 5.0
    assert_operator after_err, :<, before_err
  end

  test "free align around enemy corner works for wide infantry on a flank corner" do
    # Battle 28 paid landing: skeletons' front vs orc front-right corner.
    attacker = combatant(
      entity_id: "skeletons",
      x: 15.186967578348623,
      y: 6.466367818559672,
      facing: 29.274246621326142,
      base_width: 5,
      base_depth: 4,
      files: 5,
      ranks: 4
    )
    defender = combatant(
      entity_id: "orks",
      x: 17.759101778491914,
      y: 10.479726120756125,
      facing: 176.6599179970599,
      base_width: 4,
      base_depth: 2,
      files: 4,
      ranks: 2,
      side_index: 1
    )

    desired = BF.facing_into_contact_face(attacker, defender)
    before_err = BF.shortest_facing_delta(attacker[:facing], desired).abs
    assert_operator before_err, :>, 40

    aligned = BF.align_fronts_pose(attacker, defender)
    after_err = BF.shortest_facing_delta(aligned[:facing], desired).abs

    refute BF.rectangles_overlap?(aligned, defender)
    assert_operator BF.distance_between_units(aligned, defender), :<=, ENGAGE
    assert_operator after_err, :<, 8.0
    assert_operator after_err, :<, before_err * 0.35
  end

  test "free align prefers the rotation toward an unoccupied defender side" do
    attacker = combatant(
      entity_id: "a1",
      x: 12.0,
      y: 12.0,
      facing: 20.0,
      base_width: 4,
      base_depth: 2,
      files: 4,
      ranks: 2,
      movement: 1
    )
    defender = combatant(
      entity_id: "e1",
      x: 16.0,
      y: 12.5,
      facing: 180.0,
      base_width: 3,
      base_depth: 2,
      files: 3,
      ranks: 2,
      side_index: 1
    )
    # Ally already glued on the defender's +lateral half — align should favor the free half.
    ally = combatant(
      entity_id: "ally",
      x: 16.0,
      y: 15.2,
      facing: 270.0,
      base_width: 2,
      base_depth: 2,
      side_index: 0,
      current_health: 4
    )

    # Force engage geometry if needed by snapping attacker into contact band.
    unless BF.distance_between_units(attacker, defender) <= ENGAGE
      dest = BF.charge_destination(attacker, defender)
      attacker[:x] = dest[:x]
      attacker[:y] = dest[:y]
      attacker[:facing] = dest[:facing]
    end
    assert_operator BF.distance_between_units(attacker, defender), :<=, ENGAGE + 0.2

    aligned = BF.align_fronts_pose(attacker, defender, obstacles: [ ally ])
    local = BF.point_in_local_unit_space(aligned, defender)
    ally_local = BF.point_in_local_unit_space(ally, defender)
    # Prefer opposite lateral half from the ally when both rotates are otherwise viable.
    refute_equal local[:lateral] >= 0, ally_local[:lateral] >= 0 if BF.front_contact_span(aligned, defender) > 0.5
  end

  test "free align turns the other way when short wheel hits an idle friend" do
    # Battle 32 R4: boars free-align into enemy boars; idle orks sit on the short arc.
    attacker = combatant(
      entity_id: "boars",
      name: "Наездники на кабанах",
      x: 13.376153553243148,
      y: 5.420222533206636,
      facing: 6.819621777195266,
      base_width: 3,
      base_depth: 4,
      files: 3,
      ranks: 4,
      side_index: 0
    )
    defender = combatant(
      entity_id: "enemy_boars",
      name: "Наездники на кабанах",
      x: 18.067680039221827,
      y: 4.8691417219680595,
      facing: 123.73674960188418,
      base_width: 3,
      base_depth: 4,
      files: 3,
      ranks: 4,
      side_index: 1
    )
    ally = combatant(
      entity_id: "orks",
      name: "Орки-бойзы",
      x: 15.493154665390248,
      y: 8.641356531078802,
      facing: 270.0,
      base_width: 4,
      base_depth: 2,
      side_index: 0,
      current_health: 10
    )

    assert_operator BF.distance_between_units(attacker, defender), :<=, ENGAGE
    assert_operator BF.distance_between_units(ally, defender), :>, ENGAGE
    assert_operator BF.distance_between_units(attacker, ally), :<=, BF.idle_ally_proximity_limit(attacker)

    desired = BF.facing_into_contact_face(attacker, defender)
    short = BF.shortest_facing_delta(attacker[:facing], desired)
    pivot = BF.contact_pivot_point(attacker, defender)
    assert BF.align_direction_blocked_by_idle_ally?(
      attacker, pivot, short, defender, BF.idle_ally_obstacles(attacker, defender, [ ally ])
    )

    aligned = BF.align_fronts_pose(attacker, defender, obstacles: [ ally ])
    turned = BF.shortest_facing_delta(attacker[:facing], aligned[:facing])
    # Old bug: tiny nudge into the ally (~-8°). Now swing the other way.
    assert_operator turned.abs, :>, 20.0
    assert_operator turned * short, :<, 0
  end

  test "free align ignores distant idle allies for free_side scoring" do
    # Battle 33 R4: routing halberds at north edge; distant boyz must not force a 330° swing.
    attacker = combatant(
      entity_id: "unit-10",
      name: "Наездники на кабанах",
      x: 16.56397544379782,
      y: 1.9303605191445743,
      facing: 209.21375744971647,
      base_width: 1,
      base_depth: 2,
      files: 1,
      ranks: 1,
      side_index: 1
    )
    defender = combatant(
      entity_id: "unit-33",
      name: "Алебардисты",
      x: 14.385688814270203,
      y: 0.7714670386210112,
      facing: 270.0,
      base_width: 2,
      base_depth: 1,
      files: 2,
      ranks: 1,
      side_index: 0,
      is_routing: true,
      current_health: 2
    )
    distant_ally = combatant(
      entity_id: "unit-9",
      name: "Орки-бойзы",
      x: 24.487755750001995,
      y: 11.712838098019661,
      facing: 175.98729133234053,
      base_width: 4,
      base_depth: 4,
      files: 4,
      ranks: 4,
      side_index: 1,
      current_health: 16
    )

    assert_operator BF.distance_between_units(attacker, defender), :<=, ENGAGE
    assert_operator BF.distance_between_units(attacker, distant_ally), :>, BF.idle_ally_proximity_limit(attacker)
    assert_empty BF.idle_ally_obstacles(attacker, defender, [ distant_ally ])

    desired = BF.facing_into_contact_face(attacker, defender)
    short = BF.shortest_facing_delta(attacker[:facing], desired)
    aligned = BF.align_fronts_pose(attacker, defender, obstacles: [ distant_ally ])
    after_err = BF.shortest_facing_delta(aligned[:facing], desired).abs
    turned = BF.shortest_facing_delta(attacker[:facing], aligned[:facing])

    # Short flush align (~180°), not the old long free_side detour (~316°).
    assert_operator after_err, :<, 5.0
    assert_in_delta short, turned, 5.0
  end

  test "free align prefers short flush over long free_side when idle hero is nearby" do
    # Battle 60 R5: grave guards free-align into skeletons; nearby lich must not force ~83° sideways.
    attacker = combatant(
      entity_id: "unit-15",
      name: "Стража могил",
      x: 22.324,
      y: 13.513,
      facing: 142.72495616837273,
      base_width: 4,
      base_depth: 1,
      files: 4,
      ranks: 1,
      side_index: 1,
      current_health: 4
    )
    defender = combatant(
      entity_id: "unit-9",
      name: "Скелетный блок",
      x: 19.204533498751363,
      y: 12.46938440708418,
      facing: 348.02376269108777,
      base_width: 5,
      base_depth: 3,
      files: 5,
      ranks: 3,
      side_index: 0,
      current_health: 14
    )
    idle_hero = combatant(
      entity_id: "hero-3",
      name: "Король-лич",
      x: 26.853,
      y: 15.390,
      facing: 199.19,
      base_width: 1,
      base_depth: 1,
      files: 1,
      ranks: 1,
      side_index: 1,
      current_health: 1
    )

    assert_operator BF.distance_between_units(attacker, defender), :<=, ENGAGE
    assert BF.idle_ally_obstacles(attacker, defender, [ idle_hero ]).any?

    desired = BF.facing_into_contact_face(attacker, defender)
    short = BF.shortest_facing_delta(attacker[:facing], desired)
    pivot = BF.contact_pivot_point(attacker, defender)
    refute BF.align_direction_blocked_by_idle_ally?(
      attacker, pivot, short, defender, BF.idle_ally_obstacles(attacker, defender, [ idle_hero ])
    )

    aligned = BF.align_fronts_pose(attacker, defender, obstacles: [ idle_hero ])
    after_err = BF.shortest_facing_delta(aligned[:facing], desired).abs
    turned = BF.shortest_facing_delta(attacker[:facing], aligned[:facing])

    # Old bug: long free_side arc stopped near 83° (facing err ~84°). Prefer short flush (~168°).
    assert_operator after_err, :<, 5.0
    assert_in_delta short, turned, 5.0
    assert_operator BF.front_contact_span(aligned, defender), :>=, BF.front_contact_span(attacker, defender)
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
