require "test_helper"

class SimBattleFootprintSyncTest < ActiveSupport::TestCase
  test "casualty shrink trims rear ranks and keeps formation center" do
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
    front_before = Sim::Geometry::Battlefield.front_center(combatant)
    center_before = { x: combatant[:x], y: combatant[:y] }

    combatant[:current_health] = 3
    Sim::Battle::State.sync_combatant_footprint!(combatant)

    assert_equal 3, combatant[:models_remaining]
    assert_equal 1, combatant[:ranks]
    assert_in_delta 3.0, combatant[:base_width], 0.001
    assert_in_delta 1.0, combatant[:base_depth], 0.001
    assert_in_delta center_before[:x], combatant[:x], 0.001
    assert_in_delta center_before[:y], combatant[:y], 0.001

    front_after = Sim::Geometry::Battlefield.front_center(combatant)
    # Front edge moves back toward the center — rear was cut, not a forward lunge.
    assert_operator(
      Sim::Geometry::Battlefield.distance_between(front_before, center_before),
      :>,
      Sim::Geometry::Battlefield.distance_between(front_after, { x: combatant[:x], y: combatant[:y] }) - 0.05
    )
  end

  test "shrink does not create overlap with a unit already at the front" do
    warboss = {
      entity_id: "hero-2",
      name: "Варбосс",
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

    refute Sim::Geometry::Battlefield.rectangles_overlap?(warboss, boars)
    dist_before = Sim::Geometry::Battlefield.distance_between_units(warboss, boars)

    boars[:current_health] = 3
    Sim::Battle::State.sync_combatant_footprint!(boars)

    refute Sim::Geometry::Battlefield.rectangles_overlap?(warboss, boars)
    dist_after = Sim::Geometry::Battlefield.distance_between_units(warboss, boars)
    assert_operator dist_after, :>=, dist_before - 0.05
  end
end
