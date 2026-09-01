require "test_helper"

class SimBattleMarchMovementTest < ActiveSupport::TestCase
  test "infantry keeps a normal MV budget when the tray is clear to march" do
    infantry = unit(movement: 4, abilities: [])
    enemy = unit(entity_id: "enemy-1", x: 30.0, y: 12.0, movement: 4)

    budget = Sim::Battle::Decisions::Movement.budget_for(infantry, enemies: [ enemy ])
    meta = Sim::Battle::Decisions::Movement.budget_meta(infantry, enemies: [ enemy ])

    assert_in_delta 4.0, budget, 0.001
    assert_equal "active", meta[:march]
    assert_in_delta 2.0, meta[:march_multiplier], 0.001
  end

  test "infantry keeps base movement when enemy is within march clearance" do
    infantry = unit(x: 10.0, y: 12.0, movement: 4, abilities: [])
    enemy = unit(entity_id: "enemy-1", x: 16.0, y: 12.0, movement: 4, base_width: 4, base_depth: 2)

    budget = Sim::Battle::Decisions::Movement.budget_for(infantry, enemies: [ enemy ])
    meta = Sim::Battle::Decisions::Movement.budget_meta(infantry, enemies: [ enemy ])

    assert_in_delta 4.0, budget, 0.001
    assert_equal "blocked", meta[:march]
    assert_equal "enemy-1", meta[:march_blocker_id]
    assert_operator meta[:march_blocker_dist], :<=, Sim::Geometry::Battlefield::CONFIG[:march_clearance_inches]
  end

  test "flying, machine, and undead units ignore march multiplier" do
    flyer = unit(movement: 20, abilities: [ "flying" ])
    cannon = unit(movement: 2, abilities: [ "machine", "ranged" ])
    skeletons = unit(movement: 3, abilities: [ "undead", "fear" ])
    enemy = unit(entity_id: "enemy-1", x: 30.0, y: 12.0)

    assert_in_delta 20.0, Sim::Battle::Decisions::Movement.budget_for(flyer, enemies: [ enemy ]), 0.001
    assert_empty Sim::Battle::Decisions::Movement.budget_meta(flyer, enemies: [ enemy ])

    assert_in_delta 2.0, Sim::Battle::Decisions::Movement.budget_for(cannon, enemies: [ enemy ]), 0.001
    assert_empty Sim::Battle::Decisions::Movement.budget_meta(cannon, enemies: [ enemy ])

    assert_in_delta 3.0, Sim::Battle::Decisions::Movement.budget_for(skeletons, enemies: [ enemy ]), 0.001
    assert_empty Sim::Battle::Decisions::Movement.budget_meta(skeletons, enemies: [ enemy ])
  end

  test "march pathing wheels then travels double MV on leftover budget when the tray is clear" do
    infantry = unit(x: 28.1, y: 11.0, facing: 177.83, movement: 3.0, entity_id: "orc-1")
    enemy = unit(entity_id: "enemy-1", x: 4.0, y: 12.0, movement: 3, facing: 0.0)
    meta = Sim::Battle::Decisions::Movement.budget_meta(infantry, enemies: [ enemy ])
    plan = Sim::Battle::Pathing.plan_approach(
      origin: infantry,
      goal_point: enemy,
      budget: 3.0,
      obstacles: [ infantry, enemy ],
      contact_id: enemy[:entity_id],
      goal_unit: enemy,
      bypass: false,
      march_allowed: meta[:march].to_s == "active"
    )

    assert_equal "active", meta[:march]
    assert_equal :march, plan[:maneuver]
    assert_operator plan[:mv_spent_march].to_f, :>, 0.05
    travel = Sim::Geometry::Battlefield.distance_between(infantry, plan[:pose])
    assert_operator travel, :>, 4.5
    assert_in_delta 3.0, plan[:wheel][:cost].to_f + plan[:mv_spent_march].to_f, 0.2
  end

  test "march pathing travels double MV straight when the tray is clear" do
    infantry = BattleScenarios.combatant(x: 8.0, y: 12.0, facing: 0.0, movement: 4.0)
    enemy = BattleScenarios.enemy(x: 32.0, y: 12.0, facing: 180.0)
    meta = Sim::Battle::Decisions::Movement.budget_meta(infantry, enemies: [ enemy ])
    plan = Sim::Battle::Pathing.plan_approach(
      origin: infantry,
      goal_point: enemy,
      budget: 4.0,
      obstacles: [ infantry, enemy ],
      contact_id: enemy[:entity_id],
      goal_unit: enemy,
      bypass: false,
      march_allowed: meta[:march].to_s == "active"
    )

    assert_equal "active", meta[:march]
    assert_equal :march, plan[:maneuver]
    assert_in_delta 8.0, plan[:pose][:x] - infantry[:x], 0.2
  end

  test "routing enemies still block march clearance" do
    infantry = unit(x: 10.0, y: 12.0, movement: 4, abilities: [])
    routing_enemy = unit(entity_id: "enemy-1", x: 16.0, y: 12.0, is_routing: true)

    budget = Sim::Battle::Decisions::Movement.budget_for(infantry, enemies: [ routing_enemy ])

    assert_in_delta 4.0, budget, 0.001
  end

  private

  def unit(overrides = {})
    {
      entity_id: "unit-1",
      name: "Test Unit",
      x: 10.0,
      y: 12.0,
      facing: 0.0,
      base_width: 4,
      base_depth: 2,
      movement: 4,
      current_health: 10,
      is_routing: false,
      abilities: []
    }.merge(overrides)
  end
end
