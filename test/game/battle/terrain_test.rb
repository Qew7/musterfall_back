require "test_helper"

class SimBattleTerrainTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  Pathing = Sim::Battle::Pathing
  TerrainMap = Sim::Battle::TerrainMap
  Attack = Sim::Battle::Phases::AttackResolution
  DecisionsMovement = Sim::Battle::Decisions::Movement

  def house(x:, y:, width: 3, depth: 3, id: "terrain-house")
    {
      id: id,
      type: "house",
      x: x,
      y: y,
      width: width,
      depth: depth,
      impassable: true,
      blocks_los: true,
      move_cost: 1.0
    }
  end

  def lake(x:, y:, width: 4, depth: 3, id: "terrain-lake")
    {
      id: id,
      type: "lake",
      x: x,
      y: y,
      width: width,
      depth: depth,
      impassable: true,
      blocks_los: false,
      move_cost: 1.0
    }
  end

  def difficult(x:, y:, width: 4, depth: 4, id: "terrain-diff")
    {
      id: id,
      type: "difficult",
      x: x,
      y: y,
      width: width,
      depth: depth,
      impassable: false,
      blocks_los: false,
      move_cost: 2.0
    }
  end

  def forest(x:, y:, width: 5, depth: 5, id: "terrain-forest")
    {
      id: id,
      type: "forest",
      x: x,
      y: y,
      width: width,
      depth: depth,
      impassable: false,
      blocks_los: false,
      move_cost: 1.0
    }
  end

  def unit(attrs)
    {
      entity_id: attrs.fetch(:entity_id),
      name: attrs[:name] || attrs.fetch(:entity_id),
      x: attrs.fetch(:x),
      y: attrs.fetch(:y),
      facing: attrs.fetch(:facing, 0),
      base_width: attrs.fetch(:base_width, 2),
      base_depth: attrs.fetch(:base_depth, 2),
      current_health: attrs.fetch(:current_health, 10),
      movement: attrs.fetch(:movement, 6),
      skill: attrs.fetch(:skill, 4),
      side_index: attrs.fetch(:side_index, 0),
      abilities: attrs.fetch(:abilities, [])
    }
  end

  test "map_seed is stable per rng_seed and round" do
    assert_equal TerrainMap.map_seed(rng_seed: 42, round: 1), TerrainMap.map_seed(rng_seed: 42, round: 1)
    refute_equal TerrainMap.map_seed(rng_seed: 42, round: 1), TerrainMap.map_seed(rng_seed: 42, round: 2)
  end

  test "generate is deterministic and stays in the neutral zone" do
    seed = TerrainMap.map_seed(rng_seed: 99, round: 3)
    first = TerrainMap.generate(seed: seed)
    second = TerrainMap.generate(seed: seed)
    assert_equal first, second
    assert_operator first.length, :>=, 1

    depth = BF::CONFIG[:deployment_depth]
    width = BF::CONFIG[:width]
    first.each do |feature|
      half_w = feature[:width] / 2.0
      assert_operator feature[:x] - half_w, :>=, depth - 0.01
      assert_operator feature[:x] + half_w, :<=, width - depth + 0.01
      assert_includes %w[house lake difficult forest], feature[:type]
    end
  end

  test "house blocks LOS and lake does not" do
    attacker = unit(entity_id: "a", x: 12, y: 12, facing: 0)
    defender = unit(entity_id: "d", x: 28, y: 12, facing: 180)
    building = house(x: 20, y: 12)
    water = lake(x: 20, y: 12)

    assert BF.line_of_sight_blockers(attacker, defender, [], terrain: [ building ]).any?
    assert_empty BF.line_of_sight_blockers(attacker, defender, [], terrain: [ water ])
  end

  test "impassable terrain blocks ground pathing and flyer landing" do
    origin = unit(entity_id: "walker", x: 12, y: 12, facing: 0, movement: 8)
    building = house(x: 16, y: 12, width: 3, depth: 3)
    obstacles = Pathing.merge_obstacles([], [ building ])

    plan = Pathing.plan_approach(
      origin: origin,
      goal_point: { x: 22, y: 12 },
      budget: 8,
      obstacles: obstacles,
      bypass: true,
      terrain: [ building ]
    )
    assert plan[:pose]
    assert_operator plan[:pose][:x], :<, 16, "ground unit should stop before the house"

    flyer = origin.merge(entity_id: "flyer", abilities: [ "flying" ])
    leap = Sim::Battle::Rules::Flying::Movement.plan_flyer_leap(
      origin: flyer,
      goal_point: { x: 16, y: 12 },
      facing: 0,
      budget: 8,
      obstacles: obstacles
    )
    assert leap.nil? || !BF.rectangles_overlap?(
      flyer.merge(x: leap[:pose][:x], y: leap[:pose][:y]),
      BF.feature_as_obstacle(building)
    ), "flyer must not land inside a house"
  end

  test "difficult terrain costs double movement for ground units" do
    origin = unit(entity_id: "walker", x: 14, y: 12, facing: 0, movement: 4)
    rough = difficult(x: 16, y: 12, width: 6, depth: 4)
    assert BF.in_difficult?(origin.merge(x: 16, y: 12), [ rough ])

    clear_plan = Pathing.plan_approach(
      origin: origin,
      goal_point: { x: 20, y: 12 },
      budget: 4,
      obstacles: [],
      bypass: false,
      terrain: [],
      flying: false
    )
    rough_plan = Pathing.plan_approach(
      origin: origin,
      goal_point: { x: 20, y: 12 },
      budget: 4,
      obstacles: [],
      bypass: false,
      terrain: [ rough ],
      flying: false
    )
    clear_dist = BF.distance_between(origin, clear_plan[:pose])
    rough_dist = BF.distance_between(origin, rough_plan[:pose])
    assert_operator rough_dist, :<, clear_dist * 0.75

    flyer_plan = Pathing.plan_approach(
      origin: origin.merge(abilities: [ "flying" ]),
      goal_point: { x: 20, y: 12 },
      budget: 4,
      obstacles: [],
      bypass: false,
      terrain: [ rough ],
      flying: true
    )
    flyer_dist = BF.distance_between(origin, flyer_plan[:pose])
    assert_in_delta clear_dist, flyer_dist, 0.2
  end

  test "forest soft cover reduces shooting hit chance" do
    attacker = { skill: 4 }
    defender = unit(entity_id: "def", x: 20, y: 12)
    woods = forest(x: 20, y: 12)
    open = Attack.hit_chance(attacker, defender, "shooting", terrain: [])
    covered = Attack.hit_chance(attacker, defender, "shooting", terrain: [ woods ])
    assert_in_delta 4 / 7.0, open, 0.0001
    assert_in_delta 3 / 7.0, covered, 0.0001
  end

  test "cannot charge a forest unit from outside the same forest" do
    woods = forest(x: 20, y: 12, id: "forest-a")
    other = forest(x: 20, y: 20, id: "forest-b")
    attacker = unit(entity_id: "out", x: 12, y: 12, facing: 0, side_index: 0)
    defender = unit(entity_id: "in", x: 20, y: 12, facing: 180, side_index: 1)
    ally_in = unit(entity_id: "ally", x: 21, y: 12, facing: 0, side_index: 0)

    refute DecisionsMovement.can_charge?(attacker, defender, [ woods ])
    assert DecisionsMovement.can_charge?(ally_in, defender, [ woods ])
    refute DecisionsMovement.can_charge?(
      unit(entity_id: "other-forest", x: 20, y: 20, facing: 0),
      defender,
      [ woods, other ]
    )
    assert DecisionsMovement.can_charge?(attacker, defender, [])
  end

  test "ground melee entries mark forest-hidden targets as not chargeable" do
    woods = forest(x: 22, y: 12)
    attacker = unit(entity_id: "a", x: 12, y: 12, facing: 0, movement: 8, side_index: 0)
    defender = unit(entity_id: "d", x: 22, y: 12, facing: 180, side_index: 1)
    claimed = Hash.new { |hash, key| hash[key] = {} }
    entries = Sim::Battle::Rules::Ground::Movement.plan_entries([ attacker ], [ defender ], claimed, terrain: [ woods ])
    assert_equal 1, entries.length
    assert_equal false, entries.first[:chargeable]
  end

  test "bypass can route around impassable terrain like a unit blocker" do
    origin = unit(entity_id: "a", x: 12, y: 12, facing: 0, movement: 10, base_width: 1, base_depth: 1)
    building = house(x: 16, y: 12, width: 2, depth: 4)
    obstacles = Pathing.merge_obstacles([], [ building ])
    plan = Pathing.plan_approach(
      origin: origin,
      goal_point: { x: 22, y: 12 },
      budget: 10,
      obstacles: obstacles,
      bypass: true,
      terrain: [ building ]
    )
    assert plan[:pose]
    assert plan[:avoided] || plan[:truncated]
    refute BF.rectangles_overlap?(
      origin.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing]),
      BF.feature_as_obstacle(building)
    )
  end
end
