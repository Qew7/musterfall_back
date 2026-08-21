require "test_helper"

class SimBattleActionResultTest < ActiveSupport::TestCase
  test "spell that lowers MV reports the characteristic change" do
    swordsmen = snapshot(entity_id: "swords", name: "Мечники", movement: 4)
    text = Sim::Battle::ActionResult.text_for(
      actor: { actor_role: "hero", actor_name: "Чародей Хаоса" },
      action: Sim::Battle::Spells::Shadow::Miasma,
      before: [ swordsmen ],
      after: [ swordsmen.merge(movement: 3) ]
    )

    assert_equal "Герой Чародей Хаоса окутывает Мечники миазмой: у Мечники MV уменьшился с 4 до 3.", text
  end

  test "buff on several allies reports each SK change" do
    first = snapshot(entity_id: "a", name: "Отряд 1", skill: 2)
    second = snapshot(entity_id: "b", name: "Отряд 2", skill: 3)
    text = Sim::Battle::ActionResult.text_for(
      actor: { actor_role: "hero", actor_name: "Заклинательница" },
      action: Sim::Battle::Spells::Celestial::Foresight,
      before: [ first, second ],
      after: [ first.merge(skill: 3), second.merge(skill: 4) ]
    )

    assert_equal "Герой Заклинательница дарует цели предвидение: у Отряд 1 SK увеличился с 2 до 3; у Отряд 2 SK увеличился с 3 до 4.", text
  end

  test "melee strike names weapon, armor, damage and remaining models" do
    marauders = snapshot(
      entity_id: "marauders",
      name: "Мародёры Хаоса",
      armor_type: "light",
      current_health: 10,
      models_remaining: 10
    )
    text = Sim::Battle::ActionResult.text_for(
      actor: { actor_role: "unit", actor_name: "Воины Хаоса", weapon_type: "slash" },
      action: { type: "melee" },
      before: [ marauders ],
      after: [ marauders.merge(current_health: 7, models_remaining: 7) ],
      damage: 3,
      vector: "front"
    )

    assert_equal(
      "Отряд Воины Хаоса наносит Мародёры Хаоса рубящим оружием по лёгкой броне (фронт): 3 урона, осталось 7 моделей.",
      text
    )
  end

  test "successful miasma writes the MV drop into the battlefield log" do
    host = BattleScenarios.combatant(entity_id: "mage", name: "Чародей Хаоса", x: 8.0, y: 12.0, spell: 10)
    enemy = BattleScenarios.enemy(entity_id: "swords", name: "Мечники", x: 20.0, y: 12.0, movement: 4.0)
    caster = host.merge(
      actor_id: "mage",
      actor_name: "Чародей Хаоса",
      actor_role: "hero",
      spell: 10,
      spell_range: 24,
      magic_school: "shadow"
    )
    phase = Sim::Battle::Phases::AttackResolution.create_phase("magic", "Фаза магии")

    Sim::Battle::SpellCasting.resolve_choice!(
      phase: phase,
      choice: { spell: Sim::Battle::Spells::Shadow::Miasma, target: enemy },
      caster: caster,
      host: host,
      acting_side: { side_key: "left", combatants: [ host ] },
      target_side: { side_key: "right", combatants: [ enemy ] },
      round_number: 1,
      rng: high_cast_rng,
      terrain: []
    )

    summary = phase[:actions].last[:summary]
    assert_match(/Чародей Хаоса/, summary)
    assert_match(/у Мечники MV уменьшился с 4 до 2/, summary)
    assert_equal 2.0, enemy[:movement]
  end

  test "melee resolution logs weapon versus armor and remaining models" do
    warriors = BattleScenarios.combatant(
      entity_id: "warriors",
      name: "Воины Хаоса",
      x: 10.0,
      y: 12.0,
      facing: 0,
      weapon_type: "slash",
      attacks: 1,
      skill: 6,
      contributors: {
        melee: [ { entity_id: "warriors", name: "Воины Хаоса", kind: "unit", power: 4, weapon_type: "slash" } ],
        ranged: []
      }
    )
    marauders = BattleScenarios.enemy(
      entity_id: "marauders",
      name: "Мародёры Хаоса",
      x: 12.2,
      y: 12.0,
      facing: 180,
      armor_type: "light",
      current_health: 8,
      max_health: 8,
      models_remaining: 8,
      skill: 1
    )
    phase = Sim::Battle::Phases::AttackResolution.create_phase("melee", "Ближний бой")
    rng = Object.new
    def rng.rand(_max = nil) = 0.0

    Sim::Battle::Phases::AttackResolution.resolve_melee_strike!(
      phase: phase,
      attacker: warriors,
      target: marauders,
      vector: "front",
      acting_side: { side_key: "left", combatants: [ warriors ] },
      target_side: { side_key: "right", combatants: [ marauders ] },
      round_number: 1,
      rng: rng
    )

    summary = phase[:actions].first[:summary]
    assert_match(/Воины Хаоса/, summary)
    assert_match(/рубящим оружием по лёгкой броне/, summary)
    assert_match(/осталось #{marauders[:models_remaining]} моделей/, summary)
    assert marauders[:current_health] < 8
  end

  test "spell cast line includes roll, damage and target changes" do
    fireball = Sim::Battle::Spells.fetch(:fireball)
    cast = Sim::Battle::ActionResult.text_for(
      actor: { actor_role: "hero", actor_name: "Боевой маг" },
      action: fireball,
      target_label: "Мечники",
      outcome: "success",
      dice: [ 4, 5 ],
      spell_power: 5,
      casting_total: 14,
      casting_value: 8,
      damage: 3
    )
    assert_equal "Герой Боевой маг швыряет огненный шар в Мечники: успех (4+5+5=14 против 8), 3 урона.", cast

    failed = Sim::Battle::ActionResult.text_for(
      actor: { actor_role: "hero", actor_name: "Боевой маг" },
      action: fireball,
      target_label: "Мечники",
      outcome: "failed",
      dice: [ 1, 2 ],
      spell_power: 5,
      casting_total: 8,
      casting_value: 10
    )
    assert_match(/провал \(1\+2\+5=8 против 10\)/, failed)

    delayed = Sim::Battle::ActionResult.text_for(
      action: Sim::Battle::Spells.fetch(:comet),
      target_label: "поле боя",
      outcome: "delayed",
      damage: 6
    )
    assert_equal "Комета обрушивается на поле боя: 6 урона.", delayed

    bolt = Sim::Battle::ActionResult.text_for(
      actor: { actor_role: "hero", actor_name: "Боевой маг" },
      action: { type: "magic", magic_school: "pyromancy" },
      target_name: "Мечники",
      vector: "flank",
      damage: 3
    )
    assert_match(/Герой Боевой маг направляет силу школы «Пиромантия» на Мечники \(фланг\): 3 урона\./, bolt)
  end

  private

  def snapshot(**overrides)
    {
      entity_id: "u",
      name: "Отряд",
      movement: 4,
      skill: 3,
      melee: 4,
      ranged: 0,
      morale: 6,
      spell: 0,
      current_health: 8,
      models_remaining: 8,
      armor_type: "medium",
      weapon_type: "slash"
    }.merge(overrides)
  end

  def high_cast_rng
    rng = Object.new
    def rng.rand(max = nil)
      max ? [ max.to_i - 1, 0 ].max : 0.5
    end
    rng
  end
end
