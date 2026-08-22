require "test_helper"

class SimBattleWizardCastSeekTest < ActiveSupport::TestCase
  test "thorn wall uses per-spell range of 20" do
    assert_equal 20.0, Sim::Battle::Spells::Verdancy::ThornWall.range

    host = BattleScenarios.combatant(
      entity_id: "mage",
      name: "Спеллвивер",
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
          name: "Спеллвивер",
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
      name: "Спеллвивер",
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
          name: "Спеллвивер",
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

  test "hybrid wizard out of spell range seeks instead of holding under distant LoS" do
    mage = BattleScenarios.combatant(
      entity_id: "hero-2",
      name: "Лорд-вампир",
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
          name: "Лорд-вампир",
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
