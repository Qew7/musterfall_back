require "test_helper"

class SimBattleMovementPropertiesTest < ActiveSupport::TestCase
  GENERATED_SEEDS = (1..24).to_a.freeze

  test "seeded open-field cases always make safe progress" do
    GENERATED_SEEDS.each do |seed|
      rng = Sim::Rng::Seeded.new(seed)
      actor = BattleScenarios.combatant(
        x: 4.0 + rng.rand(4),
        y: 4.0 + rng.rand(16),
        movement: 2.0 + rng.rand(5),
        base_width: 1.0 + rng.rand(4),
        base_depth: 1.0 + rng.rand(3)
      )
      target = BattleScenarios.enemy(
        x: 27.0 + rng.rand(8),
        y: 4.0 + rng.rand(16),
        base_width: 1.0 + rng.rand(4),
        base_depth: 1.0 + rng.rand(3)
      )
      actor[:facing] = Sim::Geometry::Battlefield.heading_to(actor, target)
      before = Sim::Geometry::Battlefield.distance_between_units(actor, target)
      result = run_once("generated-#{seed}", [ actor ], [ target ])
      after = Sim::Geometry::Battlefield.distance_between_units(result.actor, result.target)

      assert_operator after, :<, before, "seed=#{seed} did not make progress"
      assert BattleInvariants.verify_result!(result), "seed=#{seed}"
    rescue StandardError => error
      flunk "seed=#{seed}: #{error.class}: #{error.message}"
    end
  end

  test "permuting co-movers preserves semantic landing poses" do
    front = BattleScenarios.combatant(entity_id: "front", x: 12.0, y: 12.0)
    rear = BattleScenarios.combatant(entity_id: "rear", x: 6.0, y: 12.0, row: "support")
    target = BattleScenarios.enemy(entity_id: "target", x: 30.0, y: 12.0)

    first = run_once("front-first", [ front, rear ], [ target ])
    second = run_once("rear-first", [ rear, front ], [ target ])

    assert_equal semantic_poses(first), semantic_poses(second)
  end

  test "mirroring an open field mirrors the semantic landing" do
    actor = BattleScenarios.combatant(x: 6.0, y: 7.0)
    target = BattleScenarios.enemy(x: 28.0, y: 15.0)
    actor[:facing] = Sim::Geometry::Battlefield.heading_to(actor, target)
    mirrored_actor = mirror(actor)
    mirrored_target = mirror(target)

    original = run_once("original", [ actor ], [ target ])
    mirrored = run_once("mirrored", [ mirrored_actor ], [ mirrored_target ])

    assert_in_delta original.actor[:x], mirrored.actor[:x], 0.02
    assert_in_delta mirror_y(original.actor[:y]), mirrored.actor[:y], 0.02
    assert_in_delta mirror_facing(original.actor[:facing]), mirrored.actor[:facing], 0.05
  end

  test "a distant irrelevant obstacle does not change movement" do
    actor = BattleScenarios.combatant(x: 6.0, y: 5.0)
    target = BattleScenarios.enemy(x: 28.0, y: 5.0)
    baseline = run_once("baseline", [ actor ], [ target ])
    distant = BattleScenarios.terrain(id: "far-house", x: 20.0, y: 21.0, width: 2.0, depth: 2.0)
    obstructed = run_once("distant-obstacle", [ actor ], [ target ], terrain: [ distant ])

    assert_equal semantic_poses(baseline), semantic_poses(obstructed)
  end

  test "flying ignores path obstacles but still lands safely" do
    flyer = BattleScenarios.combatant(
      entity_id: "flyer",
      x: 6.0,
      y: 18.0,
      movement: 10.0,
      abilities: [ "flying" ]
    )
    target = BattleScenarios.enemy(x: 32.0, y: 18.0)
    house = BattleScenarios.terrain(id: "house", x: 11.0, y: 18.0, width: 2.0, depth: 2.0)
    baseline = run_once("flyer-open", [ flyer ], [ target ])
    with_house = run_once("flyer-house", [ flyer ], [ target ], terrain: [ house ])

    assert_equal semantic_poses(baseline), semantic_poses(with_house)
    assert BattleInvariants.verify_result!(with_house)
  end

  private

  def run_once(id, left, right, terrain: [])
    scenario = BattleScenarios.scenario(id: id, left: left, right: right, terrain: terrain)
    BattleScenarioRunner.new(scenario).run_movement_phase
  end

  def semantic_poses(result)
    result.acting_side[:combatants].sort_by { |unit| unit[:entity_id] }.map do |unit|
      [ unit[:entity_id], unit[:x].round(3), unit[:y].round(3), unit[:facing].round(2) ]
    end
  end

  def mirror(unit)
    unit.merge(y: mirror_y(unit[:y]), facing: mirror_facing(unit[:facing]))
  end

  def mirror_y(y)
    Sim::Geometry::Battlefield::CONFIG[:height].to_f - y.to_f
  end

  def mirror_facing(facing)
    Sim::Geometry::Battlefield.normalize_facing(-facing.to_f)
  end
end
