require "test_helper"

class SimBattleWizardCastSeekTest < ActiveSupport::TestCase
  test "thorn wall uses per-spell range of 20" do
    assert_equal 20.0, Sim::Battle::Spells::Verdancy::ThornWall.range

    host = BattleScenarios.combatant(
      entity_id: "mage",
      name: "Лесной чародей",
      x: 3.0,
      y: 8.0,
      spell: 5,
      spell_range: 8,
      spell_keys: %w[thorn_wall],
      abilities: %w[wizard],
      contributors: {
        melee: [],
        ranged: [ {
          entity_id: "mage",
          name: "Лесной чародей",
          kind: "hero",
          spell: 5,
          spell_range: 8,
          spell_keys: %w[thorn_wall],
          magic_school: "verdancy",
          initiative: 5
        } ]
      }
    )
    enemy = BattleScenarios.enemy(entity_id: "foe", name: "Враг", x: 22.0, y: 8.0)
    acting = { side_key: "left", combatants: [ host ] }
    target = { side_key: "right", combatants: [ enemy ] }

    assert Sim::Battle::Rules::Wizard::Movement.opens_cast?(
      host, acting_side: acting, target_side: target
    )

    far = BattleScenarios.enemy(entity_id: "far", name: "Далёкий", x: 30.0, y: 8.0)
    refute Sim::Battle::Rules::Wizard::Movement.opens_cast?(
      host, acting_side: acting, target_side: { side_key: "right", combatants: [ far ] }
    )
  end

  test "wizard out of cast range seeks toward a valid spell anchor" do
    mage = BattleScenarios.combatant(
      entity_id: "mage",
      name: "Лесной чародей",
      x: 3.0,
      y: 8.0,
      melee: 2,
      ranged: 0,
      spell: 5,
      spell_range: 8,
      spell_keys: %w[thorn_wall],
      movement: 4.0,
      abilities: %w[wizard],
      contributors: {
        melee: [],
        ranged: [ {
          entity_id: "mage",
          name: "Лесной чародей",
          kind: "hero",
          spell: 5,
          ranged: 0,
          spell_range: 8,
          spell_keys: %w[thorn_wall],
          magic_school: "verdancy",
          initiative: 5
        } ]
      }
    )
    enemy = BattleScenarios.enemy(entity_id: "foe", name: "Враг", x: 28.0, y: 8.0)
    acting = { side_key: "left", player_name: "Left", combatants: [ mage ] }
    target = { side_key: "right", player_name: "Right", combatants: [ enemy ] }
    before = mage[:x].to_f

    refute Sim::Battle::Rules::Wizard::Movement.opens_cast?(
      mage, acting_side: acting, target_side: target
    )

    Sim::Battle::Phases::Movement.play(
      acting_side: acting,
      target_side: target,
      round_number: 1,
      terrain: []
    )

    assert_operator mage[:x].to_f, :>, before + 0.5
  end

  test "wizard cast seek routes around impassable house with wheel or advance" do
    house = BattleScenarios.terrain(
      id: "terrain-3", type: "house", x: 12.763, y: 12.389,
      width: 3.489, depth: 2.11, impassable: true, blocks_los: true
    )
    mage = BattleScenarios.combatant(
      entity_id: "hero-1",
      name: "Некромант",
      x: 9.396,
      y: 11.791,
      facing: 357.12,
      movement: 3.0,
      spell: 5,
      spell_keys: %w[earth_split rift_lightning],
      magic_school: "ruin",
      abilities: %w[wizard],
      base_width: 1.0,
      base_depth: 1.0,
      files: 1,
      ranks: 1,
      frontage: 1,
      max_files: 1
    )
    orks = BattleScenarios.enemy(
      entity_id: "unit-5", name: "Орки-громилы",
      x: 26.53, y: 9.69, facing: 212.0,
      base_width: 4.0, base_depth: 4.0, files: 4, ranks: 4
    )
    acting = { side_key: "left", player_name: "Left", combatants: [ mage ] }
    target = { side_key: "right", player_name: "Right", combatants: [ orks ] }
    obstacles = Sim::Battle::Pathing::Obstacles.merge([ orks ], [ house ])

    refute Sim::Battle::Rules::Wizard::Movement.opens_cast?(
      mage, acting_side: acting, target_side: target, terrain: [ house ]
    )

    intent = Sim::Battle::Decisions::Reposition.build_intent(
      combatant: mage,
      acting_side: acting,
      target_side: target,
      obstacles: obstacles,
      round_number: 3,
      terrain: [ house ]
    )
    assert intent, "expected a cast-seek reposition intent beside the house"
    refute intent[:wait]

    packed = intent.merge(
      combatant: mage,
      from: mage.slice(:x, :y, :facing, :row, :lane),
      before: mage.dup,
      origin_pose: mage.dup
    )
    Sim::Battle::Phases::Movement.resolve_destination_conflicts!([ packed ], obstacles)
    refute packed[:wait], "landing beside terrain must not be rejected as ally block"

    house_obs = Sim::Geometry::Battlefield.feature_as_obstacle(house)
    landed = mage.merge(x: intent[:destination][:x], y: intent[:destination][:y], facing: intent[:destination][:facing])
    refute Sim::Geometry::Battlefield.rectangles_overlap?(landed, house_obs)

    phase = Sim::Battle::Phases::Movement.play(
      acting_side: acting,
      target_side: target,
      round_number: 3,
      terrain: [ house ]
    )
    move = phase[:actions].find { |action| action[:actor_id] == "hero-1" }
    assert move
    refute_equal move[:from][:x], move[:to][:x]
    assert move.dig(:maneuver, :avoided) || move.dig(:maneuver, :pathing_avoided) ||
      Array(move.dig(:maneuver, :steps)).any? { |step| %w[wheel turn advance march].include?(step[:kind].to_s) }
  end

  test "hybrid wizard out of spell range seeks instead of holding under distant LoS" do
    mage = BattleScenarios.combatant(
      entity_id: "hero-2",
      name: "Ночной лорд",
      x: 3.0,
      y: 8.0,
      melee: 5,
      ranged: 3,
      spell: 4,
      spell_range: 8,
      shooting_range: 9,
      spell_keys: %w[withering],
      movement: 3.0,
      abilities: %w[wizard],
      contributors: {
        melee: [],
        ranged: [ {
          entity_id: "hero-2",
          name: "Ночной лорд",
          kind: "hero",
          ranged: 3,
          spell: 4,
          spell_range: 8,
          shooting_range: 9,
          spell_keys: %w[withering],
          magic_school: "necromancy",
          initiative: 5
        } ]
      }
    )
    enemy = BattleScenarios.enemy(
      entity_id: "foe",
      name: "Некромант",
      x: 28.0,
      y: 8.0,
      melee: 1,
      ranged: 5,
      spell: 5,
      shooting_range: 9,
      spell_range: 8
    )
    acting = { side_key: "left", player_name: "Left", combatants: [ mage ] }
    target = { side_key: "right", player_name: "Right", combatants: [ enemy ] }
    before = mage[:x].to_f

    refute Sim::Battle::Rules::Wizard::Movement.opens_cast?(
      mage, acting_side: acting, target_side: target
    )

    Sim::Battle::Phases::Movement.play(
      acting_side: acting,
      target_side: target,
      round_number: 1,
      terrain: []
    )

    assert_operator mage[:x].to_f, :>, before + 0.5
  end
end
