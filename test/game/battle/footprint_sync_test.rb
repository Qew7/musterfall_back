require "test_helper"

class SimBattleFootprintSyncTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  ENGAGE = Sim::Battle::Pathing::ENGAGE
  CONTACT = Sim::Battle::Pathing::CONTACT

  test "casualty shrink trims rear ranks and keeps the front edge" do
    combatant = {
      entity_id: "boars",
      name: "Наездники на кабанах",
      x: 24.5,
      y: 18.4,
      facing: 222.0,
      base_width: 3,
      base_depth: 4,
      model_width: 1,
      model_depth: 1,
      frontage: 3,
      max_files: 5,
      files: 3,
      ranks: 2,
      current_health: 6,
      max_health: 6,
      model_health: 1,
      models_remaining: 6,
      starting_models: 6
    }
    front_before = BF.front_center(combatant)
    center_before = { x: combatant[:x], y: combatant[:y] }

    combatant[:current_health] = 3
    Sim::Battle::State.sync_combatant_footprint!(combatant)

    assert_equal 3, combatant[:models_remaining]
    assert_equal 1, combatant[:ranks]
    assert_in_delta 3.0, combatant[:base_width], 0.001
    assert_in_delta 1.0, combatant[:base_depth], 0.001

    front_after = BF.front_center(combatant)
    assert_in_delta front_before[:x], front_after[:x], 0.001
    assert_in_delta front_before[:y], front_after[:y], 0.001

    # Center advances toward the front as the rear is cut away.
    assert_operator(
      BF.distance_between(center_before, front_before),
      :>,
      BF.distance_between({ x: combatant[:x], y: combatant[:y] }, front_after) + 0.05
    )
  end

  test "shrink does not create overlap with a unit already at the front" do
    war_chief = {
      entity_id: "hero-2",
      name: "Вождь орды",
      x: 22.18,
      y: 16.44,
      facing: 237.0,
      base_width: 1,
      base_depth: 1,
      current_health: 4
    }
    boars = {
      entity_id: "unit-7",
      name: "Наездники на кабанах",
      x: 24.52,
      y: 18.36,
      facing: 222.0,
      base_width: 3,
      base_depth: 4,
      model_width: 1,
      model_depth: 1,
      frontage: 3,
      max_files: 5,
      files: 3,
      ranks: 2,
      current_health: 6,
      max_health: 6,
      model_health: 1,
      models_remaining: 6,
      starting_models: 6
    }

    refute BF.rectangles_overlap?(war_chief, boars)
    dist_before = BF.distance_between_units(war_chief, boars)

    boars[:current_health] = 3
    Sim::Battle::State.sync_combatant_footprint!(boars)

    refute BF.rectangles_overlap?(war_chief, boars)
    dist_after = BF.distance_between_units(war_chief, boars)
    assert_in_delta dist_before, dist_after, 0.05
  end

  test "shrink while in melee does not reopen a charge gap" do
    spawn = rift_mutant
    swords = imperial_swordsmen
    land_in_contact!(swords, spawn)

    gap_before = BF.distance_between_units(swords, spawn)
    assert_operator gap_before, :<=, ENGAGE
    assert_nil Sim::Battle::Decisions::Movement.build_approach_intent(
      combatant: swords,
      nearest: spawn,
      obstacles: [ spawn ]
    )

    swords[:current_health] = 8
    Sim::Battle::State.sync_combatant_footprint!(swords)

    gap_after = BF.distance_between_units(swords, spawn)
    assert_in_delta gap_before, gap_after, 0.05
    assert_operator gap_after, :<=, ENGAGE
    assert_nil Sim::Battle::Decisions::Movement.build_approach_intent(
      combatant: swords,
      nearest: spawn,
      obstacles: [ spawn ]
    )
    assert_operator gap_after, :<=, CONTACT
  end

  test "multi-rank casualties in contact never reopen approach or melee_charge" do
    spawn = rift_mutant
    swords = imperial_swordsmen
    land_in_contact!(swords, spawn)
    gap0 = BF.distance_between_units(swords, spawn)

    # 16 → 12 → 8 → 4: depth 4 → 3 → 2 → 1 while still fighting spawn.
    [ 12, 8, 4 ].each do |hp|
      swords[:current_health] = hp
      Sim::Battle::State.sync_combatant_footprint!(swords)

      gap = BF.distance_between_units(swords, spawn)
      assert_in_delta gap0, gap, 0.05, "gap drifted after HP=#{hp}"
      assert_operator gap, :<=, ENGAGE
      assert_nil Sim::Battle::Decisions::Movement.build_approach_intent(
        combatant: swords,
        nearest: spawn,
        obstacles: [ spawn ]
      ), "approach returned after shrink to HP=#{hp}"
      assert_nil Sim::Battle::Phases::AttackResolution.melee_charge(
        swords, spawn, "melee", "front"
      ), "melee_charge returned after shrink to HP=#{hp}"
    end

    assert_equal 1, swords[:ranks]
    assert_in_delta 1.0, swords[:base_depth], 0.001
  end

  test "depth growth extends the rear and keeps the front edge" do
    combatant = {
      entity_id: "undead",
      name: "Скелетный блок",
      x: 10.0,
      y: 12.0,
      facing: 0,
      base_width: 5,
      base_depth: 1,
      model_width: 1,
      model_depth: 1,
      frontage: 5,
      max_files: 5,
      files: 5,
      ranks: 1,
      current_health: 5,
      max_health: 18,
      model_health: 1,
      models_remaining: 5,
      starting_models: 18
    }
    front_before = BF.front_center(combatant)
    rear_before = {
      x: combatant[:x] - BF.unit_dimensions(combatant)[:half_depth],
      y: combatant[:y]
    }

    combatant[:current_health] = 15
    Sim::Battle::State.sync_combatant_footprint!(combatant)

    assert_equal 3, combatant[:ranks]
    assert_in_delta 3.0, combatant[:base_depth], 0.001
    front_after = BF.front_center(combatant)
    assert_in_delta front_before[:x], front_after[:x], 0.001
    assert_in_delta front_before[:y], front_after[:y], 0.001

    rear_after = {
      x: combatant[:x] - BF.unit_dimensions(combatant)[:half_depth],
      y: combatant[:y]
    }
    assert_operator rear_after[:x], :<, rear_before[:x]
  end

  test "width-only shrink does not slide the unit along facing" do
    combatant = {
      entity_id: "swords",
      name: "Имперские мечники",
      x: 12.0,
      y: 12.0,
      facing: 90,
      base_width: 4,
      base_depth: 1,
      model_width: 1,
      model_depth: 1,
      frontage: 4,
      max_files: 5,
      files: 4,
      ranks: 1,
      current_health: 4,
      max_health: 16,
      model_health: 1,
      models_remaining: 4,
      starting_models: 16
    }
    x_before = combatant[:x]
    y_before = combatant[:y]
    front_before = BF.front_center(combatant)

    combatant[:current_health] = 2
    Sim::Battle::State.sync_combatant_footprint!(combatant)

    assert_equal 2, combatant[:files]
    assert_equal 1, combatant[:ranks]
    assert_in_delta 2.0, combatant[:base_width], 0.001
    assert_in_delta 1.0, combatant[:base_depth], 0.001
    assert_in_delta x_before, combatant[:x], 0.001
    assert_in_delta y_before, combatant[:y], 0.001
    assert_in_delta front_before[:x], BF.front_center(combatant)[:x], 0.001
    assert_in_delta front_before[:y], BF.front_center(combatant)[:y], 0.001
  end

  test "movement phase stays put after casualty shrink in contact" do
    spawn = rift_mutant
    swords = imperial_swordsmen
    land_in_contact!(swords, spawn)

    swords[:current_health] = 8
    Sim::Battle::State.sync_combatant_footprint!(swords)
    before = swords.slice(:x, :y, :facing)

    Sim::Battle::Phases::Movement.play(
      acting_side: { player_id: "empire", combatants: [ swords ] },
      target_side: { player_id: "chaos", combatants: [ spawn ] }
    )

    assert_in_delta before[:x], swords[:x], 0.001
    assert_in_delta before[:y], swords[:y], 0.001
    assert_operator BF.distance_between_units(swords, spawn), :<=, ENGAGE
  end

  private

  def rift_mutant
    {
      entity_id: "spawn",
      name: "Мутант разлома",
      x: 16,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 2,
      model_width: 1,
      model_depth: 1,
      frontage: 2,
      max_files: 5,
      files: 2,
      ranks: 2,
      current_health: 12,
      max_health: 12,
      model_health: 3,
      models_remaining: 4,
      starting_models: 4,
      melee: 5,
      movement: 3,
      side_index: 1
    }
  end

  def imperial_swordsmen
    {
      entity_id: "swords",
      name: "Имперские мечники",
      x: 12,
      y: 12,
      facing: 0,
      base_width: 4,
      base_depth: 4,
      model_width: 1,
      model_depth: 1,
      frontage: 4,
      max_files: 5,
      files: 4,
      ranks: 4,
      current_health: 16,
      max_health: 16,
      model_health: 1,
      models_remaining: 16,
      starting_models: 16,
      melee: 4,
      movement: 3,
      initiative: 3,
      side_index: 0
    }
  end

  def land_in_contact!(attacker, defender)
    landed = BF.charge_destination(attacker, defender)
    attacker[:x] = landed[:x]
    attacker[:y] = landed[:y]
    attacker[:facing] = landed[:facing] if landed[:facing]
  end
end
