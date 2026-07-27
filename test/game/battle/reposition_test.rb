require "test_helper"

class SimBattleRepositionTest < ActiveSupport::TestCase
  test "archer without LoS repositions and can shoot same turn after plan" do
    # Ally body blocks LoS; MV 0 so it stays an obstacle (not a co-mover).
    # Keep the wall narrow enough that an oblique wheel+march can clear LoS and still face.
    wall = combatant(
      entity_id: "wall-1",
      name: "Стена тел",
      x: 12,
      y: 12,
      facing: 0,
      base_width: 2,
      base_depth: 1,
      melee: 5,
      ranged: 0,
      spell: 0,
      movement: 0,
      side_index: 0,
      row: "front",
      lane: "center"
    )
    archer = missile_host(
      entity_id: "archer-1",
      name: "Лучники",
      x: 8,
      y: 12,
      facing: 0,
      base_width: 1,
      base_depth: 1,
      melee: 1,
      ranged: 5,
      spell: 0,
      movement: 5,
      side_index: 0,
      row: "support",
      lane: "center"
    )
    target = combatant(
      entity_id: "enemy-1",
      name: "Орки",
      x: 18,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 1,
      melee: 2,
      ranged: 0,
      spell: 0,
      movement: 2,
      side_index: 1,
      row: "front",
      lane: "center"
    )

    acting_side = { player_id: "p1", player_name: "A", combatants: [ archer, wall ] }
    target_side = { player_id: "p2", player_name: "B", combatants: [ target ] }
    all = acting_side[:combatants] + target_side[:combatants]
    actor = Sim::Battle::Decisions::MissileChoice.build_actor(archer, archer[:contributors][:ranged].first)

    refute Sim::Battle::Decisions::MissileChoice.has_missile_option?(actor, target_side[:combatants], all, 1)

    Sim::Battle::Phases::Movement.play(
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1
    )

    all_after = acting_side[:combatants] + target_side[:combatants]
    actor_after = Sim::Battle::Decisions::MissileChoice.build_actor(archer, archer[:contributors][:ranged].first)
    assert Sim::Battle::Decisions::MissileChoice.has_missile_option?(actor_after, target_side[:combatants], all_after, 1),
           "expected LoS after reposition; pose=(#{archer[:x]}, #{archer[:y]}) f#{archer[:facing]}"

    plan = Sim::Battle::Phases::Missile.plan(
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1
    )
    assert plan.any? { |entry| entry[:attack_type] == "shooting" && entry[:host_id] == "archer-1" }
  end

  test "weak missile unit leaves charge arc of enemy melee when possible" do
    archer = missile_host(
      entity_id: "archer-1",
      name: "Лучники",
      x: 14,
      y: 12,
      facing: 90,
      melee: 1,
      ranged: 5,
      spell: 0,
      movement: 4,
      side_index: 0
    )
    enemy = combatant(
      entity_id: "enemy-1",
      name: "Рыцари",
      x: 18,
      y: 12,
      facing: 180,
      base_width: 2,
      base_depth: 1,
      melee: 8,
      ranged: 0,
      spell: 0,
      movement: 4,
      attacks: 2,
      side_index: 1
    )

    acting_side = { player_id: "p1", combatants: [ archer ] }
    target_side = { player_id: "p2", combatants: [ enemy ] }

    assert Sim::Battle::Decisions::Reposition.in_charge_danger?(archer, [ enemy ])

    Sim::Battle::Phases::Movement.play(
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1
    )

    refute Sim::Battle::Decisions::Reposition.in_charge_danger?(archer, [ enemy ]),
           "archer still in charge arc at (#{archer[:x]}, #{archer[:y]})"
  end

  test "archer leaves enemy shooting arc when threatened and has no shot" do
    enemy_shooter = missile_host(
      entity_id: "enemy-archer",
      name: "Вражеские лучники",
      x: 10,
      y: 16,
      facing: 270,
      melee: 1,
      ranged: 5,
      spell: 0,
      movement: 0,
      side_index: 1
    )
    # Lock enemy in melee on the west so the east flank stay clear for our archer to step out.
    friend = combatant(
      entity_id: "friend-1",
      name: "Союзник в бою",
      x: 8.5,
      y: 16,
      facing: 0,
      melee: 4,
      ranged: 0,
      spell: 0,
      movement: 0,
      side_index: 0
    )
    archer = missile_host(
      entity_id: "archer-1",
      name: "Лучники",
      x: 11,
      y: 12,
      facing: 0,
      base_width: 1,
      base_depth: 1,
      melee: 1,
      ranged: 4,
      spell: 0,
      movement: 4,
      side_index: 0
    )

    acting_side = { player_id: "p1", combatants: [ archer, friend ] }
    target_side = { player_id: "p2", combatants: [ enemy_shooter ] }

    assert Sim::Geometry::Battlefield.in_front_arc?(enemy_shooter, archer, enemy_shooter[:facing])
    all = acting_side[:combatants] + target_side[:combatants]
    actor = Sim::Battle::Decisions::MissileChoice.build_actor(archer, archer[:contributors][:ranged].first)
    refute Sim::Battle::Decisions::MissileChoice.has_missile_option?(actor, target_side[:combatants], all, 1)
    assert Sim::Battle::Decisions::Targeting.in_melee_combat?(enemy_shooter, all)

    Sim::Battle::Phases::Movement.play(
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1
    )

    refute Sim::Geometry::Battlefield.in_front_arc?(enemy_shooter, archer, enemy_shooter[:facing]),
           "expected to leave shooting arc; pose=(#{archer[:x]}, #{archer[:y]})"
  end

  test "reposition does not permanently block ally LoS when an open lane exists" do
    target = combatant(
      entity_id: "enemy-1",
      name: "Орки",
      x: 20,
      y: 12,
      facing: 180,
      melee: 2,
      ranged: 0,
      spell: 0,
      movement: 2,
      side_index: 1
    )
    ally = missile_host(
      entity_id: "ally-archer",
      name: "Союзные лучники",
      x: 8,
      y: 12,
      facing: 0,
      melee: 1,
      ranged: 5,
      spell: 0,
      movement: 0,
      side_index: 0
    )
    mover = missile_host(
      entity_id: "mover-1",
      name: "Перебежчики",
      x: 12,
      y: 10,
      facing: 180,
      melee: 1,
      ranged: 4,
      spell: 0,
      movement: 3,
      side_index: 0
    )

    acting_side = { player_id: "p1", combatants: [ ally, mover ] }
    target_side = { player_id: "p2", combatants: [ target ] }
    all = acting_side[:combatants] + target_side[:combatants]

    ally_actor = Sim::Battle::Decisions::MissileChoice.build_actor(ally, ally[:contributors][:ranged].first)
    assert Sim::Battle::Decisions::MissileChoice.has_missile_option?(ally_actor, [ target ], all, 1)

    Sim::Battle::Phases::Movement.play(
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1
    )

    all_after = acting_side[:combatants] + target_side[:combatants]
    ally_actor_after = Sim::Battle::Decisions::MissileChoice.build_actor(ally, ally[:contributors][:ranged].first)
    assert Sim::Battle::Decisions::MissileChoice.has_missile_option?(ally_actor_after, [ target ], all_after, 1),
           "mover blocked ally LoS at mover=(#{mover[:x]}, #{mover[:y]})"
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
      max_files: 2,
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
      attacks: 1,
      abilities: [],
      contributors: { melee: [], ranged: [] }
    }.merge(overrides)
  end

  def missile_host(**overrides)
    id = overrides[:entity_id] || "missile-1"
    name = overrides[:name] || "Стрелки"
    ranged = overrides.fetch(:ranged, 5)
    spell = overrides.fetch(:spell, 0)
    base = combatant(
      entity_id: id,
      name: name,
      melee: 1,
      ranged: ranged,
      spell: spell,
      weapon_type: "ranged",
      skill: 4,
      shooting_range: 14,
      spell_range: 8,
      shooting_template: "single",
      spell_template: "blast",
      requires_line_of_sight: true,
      missile_attacks: 1,
      row: "support"
    ).merge(overrides)
    base[:contributors] = {
      melee: [],
      ranged: [
        {
          entity_id: id,
          name: name,
          kind: "unit",
          power: ranged,
          ranged: ranged,
          spell: spell,
          skill: base[:skill],
          weapon_type: base[:weapon_type],
          abilities: Array(base[:abilities]),
          shooting_range: base[:shooting_range],
          spell_range: base[:spell_range],
          shooting_template: base[:shooting_template],
          spell_template: base[:spell_template],
          requires_line_of_sight: true,
          missile_attacks: 1,
          initiative: base[:initiative],
          experience_gain: 0
        }
      ]
    }
    base
  end
end
