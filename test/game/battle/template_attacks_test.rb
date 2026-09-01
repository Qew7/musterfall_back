require "test_helper"

class SimBattleTemplateAttacksTest < ActiveSupport::TestCase
  BF = Sim::Geometry::Battlefield
  Attack = Sim::Battle::Phases::AttackResolution
  Templates = Sim::Battle::Templates

  test "polygon counts models whose center is inside the template" do
    unit = combatant(
      x: 10, y: 12, facing: 0,
      files: 4, ranks: 1, models_remaining: 4,
      base_width: 4, base_depth: 1,
      model_width: 1, model_depth: 1
    )
    front_left = BF.model_cells(unit).first
    polygon = square_around(front_left[:x], front_left[:y], half: 0.25)

    assert_equal 1, BF.models_hit_by_polygon(unit, polygon)
  end

  test "polygon ignores models that only overlap the edge without center inside" do
    unit = combatant(
      x: 10, y: 12, facing: 0,
      files: 2, ranks: 1, models_remaining: 2,
      base_width: 2, base_depth: 1,
      model_width: 1, model_depth: 1
    )
    left, right = BF.model_cells(unit)
    polygon = square_around(left[:x], left[:y], half: 0.2)

    assert BF.point_in_polygon?({ x: left[:x], y: left[:y] }, polygon)
    refute BF.point_in_polygon?({ x: right[:x], y: right[:y] }, polygon)
    assert_equal 1, BF.models_hit_by_polygon(unit, polygon)
  end

  test "line counts models whose center lies on the segment" do
    block = combatant(
      x: 12, y: 12, facing: 180, side_index: 1,
      files: 1, ranks: 3, models_remaining: 3,
      base_width: 1, base_depth: 3,
      model_width: 1, model_depth: 1
    )
    start_point = { x: 5, y: 12 }
    end_point = { x: 25, y: 12 }

    assert_equal 3, BF.models_hit_by_line(block, start_point, end_point)
    BF.model_cells(block).each do |cell|
      assert BF.model_center_on_line?(cell, start_point, end_point)
    end
  end

  test "line ignores models whose center misses the segment" do
    block = combatant(
      x: 12, y: 14, facing: 180, side_index: 1,
      files: 1, ranks: 3, models_remaining: 3,
      base_width: 1, base_depth: 3,
      model_width: 1, model_depth: 1
    )

    assert_equal 0, BF.models_hit_by_line(block, { x: 5, y: 12 }, { x: 25, y: 12 })
  end

  test "breath template delegates hit counting to center-under-polygon rule" do
    dragon = combatant(x: 10, y: 12, facing: 0, base_width: 2, base_depth: 2, model_width: 2, model_depth: 2)
    block = combatant(
      x: 15, y: 12, facing: 180, side_index: 1,
      files: 4, ranks: 2, models_remaining: 8,
      base_width: 4, base_depth: 2,
      model_width: 1, model_depth: 1
    )
    template = Templates::Breath.new(dragon, block)
    victims = template.attack_victims([ block ])

    assert victims.any?
    assert_equal template.models_hit(block), victims.first[:models_hit]
  end

  test "line template attack victims match center-on-line count" do
    cannon = combatant(x: 5, y: 12, facing: 0, shooting_range: 20, shooting_template: "line")
    block = combatant(
      x: 12, y: 12, facing: 180, side_index: 1,
      files: 1, ranks: 3, models_remaining: 3,
      base_width: 1, base_depth: 3
    )
    victims = Templates::Line.new(cannon, block).attack_victims([ block ])

    assert_equal 1, victims.size
    assert_equal 3, victims.first[:models_hit]
  end

  test "line template resolves damage for every unit under the beam" do
    Line = Sim::Battle::Rules::Line::Shooting
    cannon = combatant(
      entity_id: "cannon",
      x: 5, y: 12, facing: 0,
      ranged: 7, shooting_template: "line", shooting_range: 16,
      weapon_type: "demolish", skill: 3, abilities: [ "ranged", "machine" ],
      missile_attacks: 1,
      contributors: {
        ranged: [ {
          entity_id: "cannon", name: "Пушка", kind: "unit", ranged: 7, skill: 3,
          weapon_type: "demolish", shooting_template: "line", missile_attacks: 1, initiative: 4
        } ],
        melee: [], spell: []
      }
    )
    front = combatant(
      entity_id: "front", x: 12, y: 12, facing: 180, side_index: 1,
      files: 1, ranks: 2, models_remaining: 2, current_health: 2, model_health: 1,
      base_width: 1, base_depth: 2
    )
    rear = combatant(
      entity_id: "rear", x: 20, y: 12, facing: 180, side_index: 1,
      files: 1, ranks: 2, models_remaining: 2, current_health: 2, model_health: 1,
      base_width: 1, base_depth: 2
    )
    victims = Line.attack_victims(cannon, front, [ front, rear ])
    phase = Attack.create_phase("shooting", "стрельба")
    actor = Sim::Battle::Decisions::MissileChoice.build_actor(cannon, cannon.dig(:contributors, :ranged).first)

    Line.resolve_missile_strike!(
      phase: phase,
      actor: actor,
      host: cannon,
      profile: actor,
      primary: front,
      vector: "front",
      victims: victims,
      attack_type: "shooting",
      acting_side: { combatants: [ cannon ] },
      target_side: { combatants: [ front, rear ] },
      round_number: 1,
      blockers: [],
      rng: Object.new.tap { |rng| rng.define_singleton_method(:rand) { 0.0 } },
      terrain: []
    )

    assert_equal 2, victims.length
    assert_operator front[:current_health], :<, 2
    assert_operator rear[:current_health], :<, 2
  end

  test "line template extends through target to the battlefield edge" do
    cannon = combatant(x: 5, y: 12, facing: 0, shooting_range: 16, shooting_template: "line", base_depth: 1)
    primary = combatant(
      entity_id: "primary", x: 12, y: 12, facing: 180, side_index: 1,
      files: 1, ranks: 1, models_remaining: 1,
      base_width: 1, base_depth: 1
    )
    rear = combatant(
      entity_id: "rear", x: 25, y: 12, facing: 180, side_index: 1,
      files: 1, ranks: 2, models_remaining: 2,
      base_width: 1, base_depth: 2
    )

    start_point, end_point = BF.line_template_segment(cannon, primary)

    assert_in_delta Sim::Geometry::Battlefield::CONFIG[:width], end_point[:x], 0.01
    assert_in_delta 12, end_point[:y], 0.01
    victims = Templates::Line.new(cannon, primary).attack_victims([ primary, rear ])

    assert_equal 2, victims.size
    assert_equal 1, victims.find { |entry| entry[:target][:entity_id] == "primary" }[:models_hit]
    assert_equal 2, victims.find { |entry| entry[:target][:entity_id] == "rear" }[:models_hit]
  end

  test "line template still respects sixteen inch targeting range" do
    cannon = combatant(x: 5, y: 12, facing: 0, shooting_range: 16, shooting_template: "line")
    near = combatant(entity_id: "near", x: 20, y: 12, side_index: 1)
    far = combatant(entity_id: "far", x: 22, y: 12, side_index: 1)

    assert Sim::Battle::Decisions::Targeting.can_target_ranged?(cannon, near, [ near ], terrain: [])
    refute Sim::Battle::Decisions::Targeting.can_target_ranged?(cannon, far, [ far ], terrain: [])
  end

  test "strike damage is capped to models_hit worth of model health" do
    template = Templates::Line.new({ x: 0, y: 0 }, { x: 1, y: 0 })
    multi_wound = { current_health: 16, model_health: 4, models_remaining: 4 }

    assert_equal 4, template.strike_damage(multi_wound, 1, 8)
    assert_equal 12, template.strike_damage(multi_wound, 3, 5)

    single_wound = { current_health: 8, model_health: 1, models_remaining: 8 }
    assert_equal 3, template.strike_damage(single_wound, 3, 12)
  end

  test "template resolve does not kill more models than centers hit" do
    dragon = combatant(
      entity_id: "dragon",
      name: "Костяной дракон",
      x: 10, y: 12, facing: 0,
      base_width: 2, base_depth: 2, model_width: 2, model_depth: 2,
      models_remaining: 1, model_health: 8, current_health: 8, max_health: 8,
      ranged: 20, shooting_template: "breath", shooting_range: 8,
      weapon_type: "breath", abilities: [ "ranged" ],
      missile_attacks: 1,
      contributors: { ranged: [ { entity_id: "dragon", name: "Костяной дракон", kind: "unit", ranged: 20, power: 20 } ], melee: [], spell: [] }
    )
    block = combatant(
      entity_id: "block",
      name: "Отряд",
      x: 15, y: 12, facing: 180, side_index: 1,
      files: 4, ranks: 2, models_remaining: 8,
      model_health: 4, current_health: 32, max_health: 32,
      base_width: 4, base_depth: 2,
      model_width: 1, model_depth: 1
    )
    template = Templates::Breath.new(dragon, block)
    victims = template.attack_victims([ block ])
    models_hit = victims.first[:models_hit]
    before_models = block[:models_remaining]
    assert_operator models_hit, :>=, 1

    phase = Attack.create_phase("shooting", "Фаза стрельбы")
    actor = {
      actor_id: "dragon",
      host_id: "dragon",
      actor_name: "Костяной дракон",
      actor_role: "unit"
    }.merge(dragon)
    victims = template.attack_victims([ block ])

    template.resolve_missile_strike!(
      phase: phase,
      actor: actor,
      host: dragon,
      profile: dragon,
      vector: "front",
      victims: victims,
      attack_type: "shooting",
      acting_side: { player_id: "p1", combatants: [ dragon ] },
      target_side: { player_id: "p2", combatants: [ block ] },
      round_number: 1,
      blockers: []
    )

    assert_operator block[:current_health], :<, 32
    assert_operator before_models - block[:models_remaining], :<=, models_hit
  end

  private

  def combatant(**overrides)
    {
      entity_id: "unit-1",
      name: "Unit",
      kind: "unit",
      side_index: 0,
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
      contributors: { melee: [], ranged: [], spell: [] }
    }.merge(overrides)
  end

  def square_around(x, y, half:)
    [
      { x: x - half, y: y - half },
      { x: x + half, y: y - half },
      { x: x + half, y: y + half },
      { x: x - half, y: y + half }
    ]
  end
end
