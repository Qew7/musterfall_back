require "test_helper"

class SimBattleSpellRuntimeTest < ActiveSupport::TestCase
  test "known spells make a caster use the dedicated casting engine" do
    caster = BattleScenarios.combatant(
      entity_id: "wizard-host",
      name: "Мечники с магом",
      x: 8.0,
      contributors: {
        melee: [],
        ranged: [
          {
            entity_id: "wizard",
            name: "Боевой маг",
            kind: "hero",
            spell: 5,
            spell_range: 24,
            spell_keys: %w[fireball cinder_shield],
            magic_school: "pyromancy",
            initiative: 5,
            experience_gain: 0
          }
        ]
      }
    )
    enemy = BattleScenarios.enemy(entity_id: "target", name: "Цель", x: 20.0)
    acting_side = { side_key: "left", combatants: [ caster ] }
    target_side = { side_key: "right", combatants: [ enemy ] }
    phase = Sim::Battle::Phases::Magic.play(
      acting_side: acting_side,
      target_side: target_side,
      round_number: 1,
      rng: Sim::Rng::Seeded.new(42),
      missile_plan: []
    )

    action = phase[:actions].find { |entry| entry[:spell_key] }
    assert action
    assert_equal "magic", action[:type]
    assert_includes %w[fireball cinder_shield], action[:spell_key]
    assert_includes %w[success failed miscast], action[:outcome]
    assert_match(/Боевой маг/, action[:summary])
    assert_equal 2, action[:dice].size
  end

  test "all registered spell effects satisfy the runtime context contract" do
    Sim::Battle::Spells::REGISTRY.each_value.flat_map(&:call).each do |spell|
      host = BattleScenarios.combatant(
        entity_id: "wizard-host",
        name: "Маг",
        x: 8.0,
        current_health: 6,
        max_health: 8,
        spell: 5
      )
      ally = BattleScenarios.combatant(
        entity_id: "ally",
        name: "Союзник",
        x: 12.0,
        y: 18.0,
        current_health: 5,
        max_health: 8,
        abilities: %w[undead]
      )
      enemy = BattleScenarios.enemy(
        entity_id: "enemy",
        name: "Враг",
        x: 20.0,
        spell: 4,
        contributors: { melee: [], ranged: [ { entity_id: "enemy-wizard", spell: 4 } ] }
      )
      context = Sim::Battle::SpellContext.new(
        caster: host.merge(actor_id: "wizard", actor_name: "Маг", actor_role: "hero", spell_range: 30),
        host: host,
        acting_side: { side_key: "left", combatants: [ host, ally ] },
        target_side: { side_key: "right", combatants: [ enemy ] },
        terrain: [],
        rng: Sim::Rng::Seeded.new(7),
        round_number: 1,
        spell: spell
      )

      target = spell.legal_targets(context).first
      assert target, "#{spell.key} should have a legal target"
      spell.resolve!(context, target)
      assert_kind_of Hash, context.result
    end
  end

  test "temporary stat effects revert on their declared turn boundary" do
    unit = BattleScenarios.combatant(movement: 4.0, melee: 3)
    side = { side_key: "left", combatants: [ unit ] }

    Sim::Battle::SpellEffects.add!(
      unit,
      key: "tailwind",
      modifiers: { movement: 2, melee: 1 },
      expires: { moment: :start_turn, side_key: "left" }
    )

    assert_equal 6.0, unit[:movement]
    assert_equal 4.0, unit[:melee]

    Sim::Battle::SpellEffects.expire!([ side ], moment: :start_turn, side_key: "left")

    assert_equal 4.0, unit[:movement]
    assert_equal 3.0, unit[:melee]
    assert_empty unit[:spell_effects]
  end

  test "grave dance clips instead of overlapping an ally" do
    dancer = BattleScenarios.combatant(
      entity_id: "dancer",
      name: "Скелеты",
      x: 8.0,
      y: 12.0,
      base_width: 2.0,
      base_depth: 2.0
    )
    ally = BattleScenarios.combatant(
      entity_id: "ally",
      name: "Рыцари",
      x: 12.0,
      y: 12.0,
      base_width: 4.0,
      base_depth: 4.0
    )
    enemy = BattleScenarios.enemy(x: 30.0, y: 12.0)
    host = BattleScenarios.combatant(entity_id: "mage", x: 8.0, y: 18.0, spell: 5)
    context = Sim::Battle::SpellContext.new(
      caster: host.merge(actor_id: "mage", actor_name: "Маг", actor_role: "hero", spell_range: 24),
      host: host,
      acting_side: { side_key: "left", combatants: [ host, dancer, ally ] },
      target_side: { side_key: "right", combatants: [ enemy ] },
      terrain: [],
      rng: Sim::Rng::Seeded.new(1),
      round_number: 1,
      spell: Sim::Battle::Spells::Necromancy::GraveDance
    )
    start_x = dancer[:x]
    Sim::Battle::Spells::Necromancy::GraveDance.resolve!(context, dancer)

    refute Sim::Geometry::Battlefield.rectangles_overlap?(dancer, ally)
    assert_operator dancer[:x], :>, start_x
    assert_operator Sim::Geometry::Battlefield.distance_between_units(dancer, ally),
      :>=, Sim::Battle::Pathing::CONTACT
  end

  test "terrain creation refuses occupied footprints" do
    unit = BattleScenarios.combatant(x: 10.0, y: 10.0)
    terrain = []

    blocked = Sim::Battle::SpellWorld.add_terrain!(
      terrain,
      type: "forest",
      x: 10.0,
      y: 10.0,
      all_combatants: [ unit ]
    )
    placed = Sim::Battle::SpellWorld.add_terrain!(
      terrain,
      type: "forest",
      x: 20.0,
      y: 10.0,
      all_combatants: [ unit ]
    )

    assert_nil blocked
    assert_equal "forest", placed[:type]
    assert_equal [ placed ], terrain
  end

  test "thorn wall on an occupied enemy point still places nearby terrain" do
    rng = high_cast_rng
    host = BattleScenarios.combatant(entity_id: "mage", name: "Маг", x: 8.0, y: 12.0, spell: 10)
    enemy = BattleScenarios.enemy(entity_id: "foe", x: 20.0, y: 12.0, base_width: 4.0, base_depth: 4.0)
    caster = host.merge(actor_id: "mage", actor_name: "Маг", actor_role: "hero", spell: 10, spell_range: 24, magic_school: "verdancy")
    terrain = []
    phase = Sim::Battle::Phases::AttackResolution.create_phase("magic", "Фаза магии")

    Sim::Battle::SpellCasting.resolve_choice!(
      phase: phase,
      choice: {
        spell: Sim::Battle::Spells::Verdancy::ThornWall,
        target: { entity_id: "foe", x: enemy[:x], y: enemy[:y], name: "точку у врага" }
      },
      caster: caster,
      host: host,
      acting_side: { side_key: "left", combatants: [ host ] },
      target_side: { side_key: "right", combatants: [ enemy ] },
      round_number: 1,
      rng: rng,
      terrain: terrain
    )

    wall = phase[:actions].last
    assert_equal "success", wall[:outcome]
    assert_equal 1, terrain.size
    assert_equal "add", wall.dig(:terrain_delta, 0, :operation)
    assert_equal "Стена шипов", terrain.first[:name]
    assert terrain.first[:impassable]
    refute_equal [ enemy[:x], enemy[:y] ], [ terrain.first[:x], terrain.first[:y] ]
  end

  test "summons join battle side but remain ephemeral campaign entities" do
    side = { side_key: "left", combatants: [] }
    summon = Sim::Battle::SpellWorld.summon!(
      side: side,
      kind: "skeletons",
      pose: { x: 8.0, y: 8.0, facing: 0.0 }
    )

    assert summon[:summoned]
    assert_equal summon, side[:combatants].first

    player = { roster: [] }
    Sim::Battle::State.sync_side!(player, side)
    assert_empty player[:roster]
  end

  test "melee buff prefers the ally nearer the enemy over a healthier rear ally" do
    host = BattleScenarios.combatant(
      entity_id: "mage",
      name: "Боевой маг",
      x: 20.0,
      y: 12.0,
      melee: 1,
      current_health: 2,
      max_health: 2,
      models_remaining: 1,
      spell: 5,
      spell_range: 24,
      spell_keys: %w[wild_fury],
      magic_school: "bestial"
    )
    rear = BattleScenarios.combatant(
      entity_id: "rear",
      name: "Тыл",
      x: 24.0,
      y: 12.0,
      melee: 4,
      current_health: 16,
      max_health: 16,
      models_remaining: 16
    )
    front = BattleScenarios.combatant(
      entity_id: "front",
      name: "Фронт",
      x: 14.0,
      y: 12.0,
      melee: 4,
      current_health: 10,
      max_health: 16,
      models_remaining: 10
    )
    enemy = BattleScenarios.enemy(entity_id: "enemy", name: "Враг", x: 8.0, y: 12.0)
    choice = Sim::Battle::SpellCasting.choose_spell(
      caster: Sim::Battle::Decisions::MissileChoice.build_actor(
        host,
        {
          entity_id: "mage-hero",
          name: "Боевой маг",
          kind: "hero",
          spell: 5,
          spell_range: 24,
          spell_keys: %w[wild_fury],
          magic_school: "bestial",
          initiative: 5,
          experience_gain: 0
        }
      ),
      host: host,
      acting_side: { side_key: "left", combatants: [ host, rear, front ] },
      target_side: { side_key: "right", combatants: [ enemy ] },
      round_number: 1,
      rng: Sim::Rng::Seeded.new(1),
      terrain: []
    )

    assert_equal "wild_fury", choice[:spell].key.to_s
    assert_equal "front", choice[:target][:entity_id]
  end

  test "wild fury SELECT_TARGETS skips pure shooters when fighters exist" do
    spell = Sim::Battle::Spells::Bestial::WildFury
    host = BattleScenarios.combatant(entity_id: "mage", x: 10.0, y: 12.0, melee: 1)
    shooter = BattleScenarios.combatant(entity_id: "guns", x: 12.0, y: 18.0, melee: 0, ranged: 5)
    fighter = BattleScenarios.combatant(entity_id: "blades", x: 14.0, y: 6.0, melee: 4, ranged: 0)
    context = Sim::Battle::SpellContext.new(
      caster: host.merge(actor_id: "mage", spell_range: 24),
      host: host,
      acting_side: { side_key: "left", combatants: [ host, shooter, fighter ] },
      target_side: { side_key: "right", combatants: [ BattleScenarios.enemy ] },
      terrain: [],
      rng: Sim::Rng::Seeded.new(1),
      round_number: 1,
      spell: spell
    )

    ids = spell.legal_targets(context).map { |target| target[:entity_id] }
    assert_includes ids, "blades"
    assert_includes ids, "mage"
    refute_includes ids, "guns"
  end

  test "successful terrain and teleport spells write analysis details" do
    rng = high_cast_rng
    host = BattleScenarios.combatant(entity_id: "mage", name: "Маг", x: 8.0, y: 12.0, spell: 10)
    ally = BattleScenarios.combatant(entity_id: "ally", name: "Союзник", x: 12.0, y: 12.0)
    enemy = BattleScenarios.enemy(x: 30.0, y: 12.0)
    caster = host.merge(actor_id: "mage", actor_name: "Маг", actor_role: "hero", spell: 10, spell_range: 24, magic_school: "verdancy")
    sides = {
      acting_side: { side_key: "left", combatants: [ host, ally ] },
      target_side: { side_key: "right", combatants: [ enemy ] }
    }
    terrain = []
    phase = Sim::Battle::Phases::AttackResolution.create_phase("magic", "Фаза магии")

    Sim::Battle::SpellCasting.resolve_choice!(
      phase: phase,
      choice: { spell: Sim::Battle::Spells::Verdancy::ThornWall, target: { x: 20.0, y: 6.0, name: "точка" } },
      caster: caster,
      host: host,
      round_number: 1,
      rng: rng,
      terrain: terrain,
      **sides
    )
    wall = phase[:actions].last
    assert_equal "success", wall[:outcome]
    assert_equal "add", wall.dig(:terrain_delta, 0, :operation)
    assert wall[:details].any? { |line| line.start_with?("terrain add ") }
    assert_match(/изменён ландшафт/, wall[:summary])
    assert_equal 1, terrain.size

    Sim::Battle::SpellCasting.resolve_choice!(
      phase: phase,
      choice: { spell: Sim::Battle::Spells::Shadow::Shadowstep, target: ally },
      caster: caster.merge(magic_school: "shadow"),
      host: host,
      round_number: 1,
      rng: rng,
      terrain: terrain,
      **sides
    )
    step = phase[:actions].last
    assert_equal "success", step[:outcome]
    teleport = step[:effects].find { |effect| effect[:kind] == "teleport" }
    assert teleport
    assert_equal 12.0, teleport.dig(:from, :x)
    assert step[:details].any? { |line| line.start_with?("teleport id=ally ") }
    assert_match(/перемещена/, step[:summary])
  end

  test "expired spell terrain is a remove action with analysis details" do
    wall = BattleScenarios.terrain(id: "thorns", type: "difficult", name: "Стена шипов").merge(
      spell_expires: { moment: :start_turn, side_key: "left" }
    )
    terrain = [ wall ]
    acting = { side_key: "left", player_id: "a", player_name: "A", combatants: [ BattleScenarios.combatant ] }
    target = { side_key: "right", player_id: "b", player_name: "B", combatants: [ BattleScenarios.enemy ] }

    turn = Sim::Battle::Turn.play(
      round_number: 1,
      acting_side: acting,
      target_side: target,
      rng: Sim::Rng::Seeded.new(1),
      terrain: terrain
    )
    expire = turn[:phases].first[:actions].find { |action| action[:outcome] == "expired" }

    assert expire
    assert_equal "remove", expire.dig(:terrain_delta, 0, :operation)
    assert_equal "thorns", expire.dig(:terrain_delta, 0, :feature, :id)
    assert expire[:details].any? { |line| line.include?("reason=expire") }
    assert_match(/Стена шипов/, expire[:summary])
    assert_empty terrain
  end

  test "spell statuses affect targeting, magic damage, shooting and flight through rules" do
    attacker = BattleScenarios.combatant(abilities: %w[flying])
    defender = BattleScenarios.enemy
    Sim::Battle::SpellEffects.add!(
      attacker,
      key: :howling_gale,
      statuses: %i[ranged_hindered],
      expires: { moment: :battle, side_key: "left" }
    )
    Sim::Battle::SpellEffects.add!(
      defender,
      key: :cloak_of_night,
      statuses: %i[ranged_hidden magic_ward],
      expires: { moment: :battle, side_key: "right" }
    )

    shooting = Sim::Battle::Rules.for(:shooting)
    refute shooting.allow_target?(attacker, defender, "shooting")
    assert shooting.allow_target?(attacker, defender, "magic")
    assert_equal 0.5, shooting.hit_chance_factor(attacker, defender, "shooting")
    assert_equal 0.5, shooting.damage_factor(attacker, defender, "magic", "front", 1)
    assert_equal attacker[:movement] * 0.5, Sim::Battle::Rules.for(:movement).movement_budget(attacker)
  end

  test "spell trigger hooks apply movement, turn and retaliation damage" do
    mover = BattleScenarios.combatant(entity_id: "mover")
    enemy = BattleScenarios.enemy(entity_id: "enemy")
    sides = [
      { side_key: "left", combatants: [ mover ] },
      { side_key: "right", combatants: [ enemy ] }
    ]
    Sim::Battle::SpellEffects.add!(
      mover,
      key: :ember_cage,
      triggers: { after_move: { damage: 3 } },
      expires: { moment: :battle, side_key: "left" }
    )
    movement = Sim::Battle::Phases::AttackResolution.create_phase("movement", "Фаза движения")
    movement[:actions] << { type: "movement", actor_id: "mover", from: { x: 0, y: 0 }, to: { x: 1, y: 0 } }
    Sim::Battle::Rules.for(:movement).after_play!(
      phase: movement,
      acting_side: sides[0],
      target_side: sides[1]
    )
    assert_equal 5, mover[:current_health]

    Sim::Battle::SpellEffects.add!(
      enemy,
      key: :withering,
      triggers: { start_turn: { damage: 2 } },
      expires: { moment: :battle, side_key: "right" }
    )
    turn = Sim::Battle::Phases::AttackResolution.create_phase("start", "Фаза начала")
    Sim::Battle::Rules.for(:turn).before_play!(
      phase: turn,
      acting_side: sides[1],
      target_side: sides[0]
    )
    assert_equal 6, enemy[:current_health]

    Sim::Battle::SpellEffects.add!(
      enemy,
      key: :cinder_shield,
      triggers: { after_melee_hit: { damage: 1 } },
      expires: { moment: :battle, side_key: "right" }
    )
    melee = Sim::Battle::Phases::AttackResolution.create_phase("melee", "Фаза боя")
    Sim::Battle::Rules.for(:melee).after_hit!(
      phase: melee,
      attacker: mover,
      defender: enemy,
      acting_side: sides[0],
      target_side: sides[1]
    )
    assert_equal 4, mover[:current_health]
    assert movement[:actions].any? { |action| action[:outcome] == "triggered" }
    assert turn[:actions].any? { |action| action[:outcome] == "triggered" }
    assert melee[:actions].any? { |action| action[:outcome] == "triggered" }
  end

  test "numeric spell durations expire after that side's turns" do
    unit = BattleScenarios.combatant
    side = { side_key: "left", combatants: [ unit ] }
    Sim::Battle::SpellEffects.add!(
      unit,
      key: :starlight,
      modifiers: { morale: 2 },
      expires: { moment: :turns, side_key: "left", remaining_turns: 2 }
    )

    Sim::Battle::SpellEffects.expire!([ side ], moment: :end_turn, side_key: "left")
    assert_equal 8.0, unit[:morale]
    assert_equal 1, unit.dig(:spell_effects, 0, :expires, :remaining_turns)

    Sim::Battle::SpellEffects.expire!([ side ], moment: :end_turn, side_key: "left")
    assert_equal 6.0, unit[:morale]
    assert_empty unit[:spell_effects]
  end

  test "doppelganger copies the ally as a timed summon" do
    spell = Sim::Battle::Spells::Shadow::Doppelganger
    host = BattleScenarios.combatant(entity_id: "mage", name: "Маг", x: 8.0, y: 12.0, melee: 1)
    ally = BattleScenarios.combatant(
      entity_id: "blades",
      name: "Мечники",
      x: 12.0,
      y: 12.0,
      melee: 5,
      current_health: 7,
      max_health: 10,
      models_remaining: 7
    )
    acting_side = { side_key: "left", combatants: [ host, ally ] }
    context = Sim::Battle::SpellContext.new(
      caster: host.merge(actor_id: "mage", spell_range: 24),
      host: host,
      acting_side: acting_side,
      target_side: { side_key: "right", combatants: [ BattleScenarios.enemy(x: 36.0, y: 12.0) ] },
      terrain: [],
      rng: Sim::Rng::Seeded.new(7),
      round_number: 1,
      spell: spell
    )

    spell.resolve!(context, ally)
    clone = acting_side[:combatants].find { |entry| entry[:summoned] }

    assert clone, "doppelganger should place a copy"
    assert_equal "doppelganger", clone[:summon_kind]
    assert_equal "Двойник (Мечники)", clone[:name]
    assert_equal ally[:melee], clone[:melee]
    assert_equal ally[:current_health], clone[:current_health]
    refute_equal ally[:entity_id], clone[:entity_id]
    assert_includes 2..4, clone[:summon_remaining_turns]
    assert_includes context.result[:summon_ids], clone[:entity_id]
    refute_includes spell.legal_targets(context), clone
  end

  test "timed summons vanish after remaining player turns" do
    clone = BattleScenarios.combatant(
      entity_id: "summon-left-1",
      name: "Двойник (Мечники)",
      summoned: true,
      summon_kind: "doppelganger",
      summon_remaining_turns: 2
    )
    acting = { side_key: "left", player_id: "a", player_name: "A", combatants: [ BattleScenarios.combatant(movement: 0) ] }
    target = { side_key: "right", player_id: "b", player_name: "B", combatants: [ BattleScenarios.enemy(x: 36.0, movement: 0) ] }
    acting[:combatants] << clone

    first = Sim::Battle::Turn.play(round_number: 1, acting_side: acting, target_side: target, rng: Sim::Rng::Seeded.new(1), terrain: [])
    assert acting[:combatants].include?(clone)
    assert_equal 1, clone[:summon_remaining_turns]
    refute first[:phases].flat_map { |phase| phase[:actions] }.any? { |action| action[:outcome] == "expired" && Array(action[:summon_ids]).include?(clone[:entity_id]) }

    second = Sim::Battle::Turn.play(round_number: 1, acting_side: acting, target_side: target, rng: Sim::Rng::Seeded.new(2), terrain: [])
    refute acting[:combatants].include?(clone)
    expire = second[:phases].flat_map { |phase| phase[:actions] }.find { |action| action[:outcome] == "expired" && Array(action[:summon_ids]).include?("summon-left-1") }
    assert expire
    assert_match(/Двойник/, expire[:summary])
  end

  test "areal spells attach a replay template on successful cast" do
    rng = high_cast_rng
    host = BattleScenarios.combatant(entity_id: "mage", name: "Маг", x: 8.0, y: 12.0, spell: 10)
    enemy = BattleScenarios.enemy(x: 20.0, y: 12.0)
    caster = host.merge(actor_id: "mage", actor_name: "Маг", actor_role: "hero", spell: 10, spell_range: 30, magic_school: "pyromancy")
    phase = Sim::Battle::Phases::AttackResolution.create_phase("magic", "Фаза магии")

    Sim::Battle::SpellCasting.resolve_choice!(
      phase: phase,
      choice: { spell: Sim::Battle::Spells::Pyromancy::Inferno, target: { x: 18.0, y: 12.0, name: "точка" } },
      caster: caster,
      host: host,
      acting_side: { side_key: "left", combatants: [ host ] },
      target_side: { side_key: "right", combatants: [ enemy ] },
      round_number: 1,
      rng: rng,
      terrain: []
    )
    action = phase[:actions].last
    assert_equal "success", action[:outcome]
    assert_equal "circle", action.dig(:template, :shape)
    assert_equal "inferno", action.dig(:template, :kind)
    assert_in_delta 4.0, action.dig(:template, :radius)
    assert_in_delta 18.0, action.dig(:template, :center, :x)
    assert action[:details].any? { |line| line.start_with?("template shape=circle") }
  end

  def high_cast_rng
    rng = Object.new
    def rng.rand(max = nil)
      max ? [ max.to_i - 1, 0 ].max : 0.5
    end
    rng
  end
end
