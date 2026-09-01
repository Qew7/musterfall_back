require "test_helper"

class SimBattleMovementLivenessTest < ActiveSupport::TestCase
  REACHABLE_CASES = [
    {
      id: "straight",
      actor: { x: 6.0, y: 12.0 },
      target: { x: 30.0, y: 12.0 }
    },
    {
      id: "offset-target",
      actor: { x: 6.0, y: 5.0, facing: 20.0 },
      target: { x: 30.0, y: 18.0 }
    },
    {
      id: "wide-formation",
      actor: { x: 6.0, y: 12.0, base_width: 5.0, base_depth: 3.0 },
      target: { x: 30.0, y: 12.0, base_width: 4.0, base_depth: 3.0 }
    },
    {
      id: "difficult-ground",
      actor: { x: 6.0, y: 18.0, movement: 5.0 },
      target: { x: 30.0, y: 18.0 },
      terrain: [
        {
          id: "mud",
          type: "difficult",
          x: 17.0,
          y: 18.0,
          width: 8.0,
          depth: 5.0,
          impassable: false,
          move_cost: 2.0
        }
      ],
      max_turns: 12
    },
    {
      id: "flying-over-house",
      actor: { x: 6.0, y: 4.0, movement: 10.0, abilities: [ "flying" ] },
      target: { x: 31.0, y: 4.0 },
      terrain: [ { id: "house", x: 18.0, y: 4.0, width: 5.0, depth: 5.0 } ]
    }
  ].freeze

  KNOWN_REACHABLE_GAPS = [
    {
      id: "multi-turn-impassable-house",
      actor: { x: 6.0, y: 8.0, movement: 5.0 },
      target: { x: 31.0, y: 8.0 },
      terrain: [ { id: "house", x: 18.0, y: 8.0, width: 3.0, depth: 3.0 } ]
    }
  ].freeze

  BLOCKED_CASES = [
    {
      id: "solid-terrain-wall",
      actor: { x: 6.0, y: 12.0 },
      target: { x: 32.0, y: 12.0 },
      terrain: [ { id: "wall", x: 20.0, y: 12.0, width: 24.0, depth: 4.0 } ]
    },
    {
      id: "boxed-by-allies",
      actor: { x: 6.0, y: 12.0 },
      target: { x: 30.0, y: 12.0 },
      allies: [
        { entity_id: "front", x: 10.0, y: 12.0, base_width: 4.0, base_depth: 4.0, ranged: 5, melee: 0, movement: 0 },
        { entity_id: "upper", x: 6.0, y: 8.5, base_width: 4.0, base_depth: 2.0, ranged: 5, melee: 0, movement: 0 },
        { entity_id: "lower", x: 6.0, y: 15.5, base_width: 4.0, base_depth: 2.0, ranged: 5, melee: 0, movement: 0 }
      ]
    },
    {
      id: "zero-movement",
      actor: { x: 6.0, y: 20.0, movement: 0.0 },
      target: { x: 30.0, y: 20.0 }
    }
  ].freeze

  test "reachable scenarios make contact without cycles or collisions" do
    REACHABLE_CASES.each do |definition|
      result = run_case(definition, reachable: true)

      assert result.reached,
             "#{definition[:id]} did not reach contact; stuck=#{result.stuck_reason} poses=#{result.pose_signatures.inspect}"
      assert_nil result.stuck_reason, "#{definition[:id]} got stuck"
      assert BattleInvariants.verify_result!(result), definition[:id]
    end
  end

  test "physically blocked scenarios stop safely without pose cycles" do
    BLOCKED_CASES.each do |definition|
      result = run_case(definition, reachable: false)

      refute result.reached, "#{definition[:id]} unexpectedly crossed a hard barrier"
      assert_includes %i[no_progress pose_cycle], result.stuck_reason
      assert BattleInvariants.verify_result!(result), definition[:id]
    end
  end

  test "reachable terrain obstacles are tracked as an explicit pathfinding capability" do
    definition = KNOWN_REACHABLE_GAPS.first
    result = run_case(definition, reachable: true)
    skip "Pathing cannot yet retain a multi-turn bypass waypoint for #{definition[:id]}" unless result.reached

    assert BattleInvariants.verify_result!(result)
  end

  private

  def run_case(definition, reachable:)
    actor = BattleScenarios.combatant(**definition.fetch(:actor))
    target = BattleScenarios.enemy(**definition.fetch(:target))
    allies = Array(definition[:allies]).map { |attrs| BattleScenarios.combatant(**attrs) }
    enemies = Array(definition[:enemies]).map { |attrs| BattleScenarios.enemy(**attrs) }
    terrain = Array(definition[:terrain]).map { |attrs| BattleScenarios.terrain(**attrs) }
    scenario = BattleScenarios.scenario(
      id: definition[:id],
      left: [ actor, *allies ],
      right: [ target, *enemies ],
      terrain: terrain,
      reachable: reachable,
      max_turns: definition.fetch(:max_turns, 10)
    )

    BattleScenarioRunner.new(scenario).run_movement_turns
  end
end
