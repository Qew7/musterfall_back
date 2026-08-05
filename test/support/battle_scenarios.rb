module BattleScenarios
  DEFAULT_COMBATANT = {
    entity_id: "unit-1",
    name: "Test Unit",
    kind: "unit",
    side_index: 0,
    side_key: "left",
    lane: "center",
    row: "front",
    x: 6.0,
    y: 12.0,
    facing: 0.0,
    base_width: 2.0,
    base_depth: 2.0,
    model_width: 1.0,
    model_depth: 1.0,
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
    movement: 4.0,
    abilities: [],
    contributors: { ranged: [], melee: [] }
  }.freeze

  DEFAULT_TERRAIN = {
    id: "terrain-1",
    type: "house",
    name: "Terrain",
    x: 20.0,
    y: 12.0,
    width: 4.0,
    depth: 4.0,
    impassable: true,
    blocks_los: true,
    move_cost: 1.0
  }.freeze

  module_function

  def combatant(**overrides)
    Marshal.load(Marshal.dump(DEFAULT_COMBATANT)).merge(overrides)
  end

  def enemy(**overrides)
    combatant(
      entity_id: "enemy-1",
      name: "Enemy",
      side_index: 1,
      side_key: "right",
      x: 32.0,
      facing: 180.0,
      **overrides
    )
  end

  def terrain(**overrides)
    Marshal.load(Marshal.dump(DEFAULT_TERRAIN)).merge(overrides)
  end

  def scenario(id:, left:, right:, terrain: [], actor_id: nil, target_id: nil,
    reachable: nil, max_turns: 8, expectations: {})
    left_units = left.is_a?(Array) ? left : [ left ]
    right_units = right.is_a?(Array) ? right : [ right ]
    {
      id: id.to_s,
      left: left_units,
      right: right_units,
      terrain: Array(terrain),
      actor_id: actor_id || left_units.first&.dig(:entity_id),
      target_id: target_id || right_units.first&.dig(:entity_id),
      reachable: reachable,
      max_turns: max_turns,
      expectations: expectations
    }
  end
end
