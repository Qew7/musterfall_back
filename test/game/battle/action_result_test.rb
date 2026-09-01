require "test_helper"

class SimBattleActionResultTest < ActiveSupport::TestCase
  test "strike summary appends rule clauses after after-hit effects" do
    before = {
      entity_id: "swords", name: "Мечники", armor_type: "medium",
      current_health: 8, models_remaining: 8, skill: 4, melee: 5
    }
    after = before.merge(current_health: 4, models_remaining: 4, skill: 3, melee: 4)
    line = Sim::Battle::ActionResult.text_for(
      actor: { actor_name: "Генерал", actor_role: "hero", weapon_type: "slash" },
      action: { type: "melee" },
      before: [ before ],
      after: [ after ],
      damage: 4,
      vector: "front",
      clauses: [ "токсин снижает SK и ML цели на 1 до конца боя" ]
    )

    assert_match(/Герой Генерал наносит Мечники/, line)
    assert_match(/4 урона/, line)
    assert_match(/осталось 4 моделей/, line)
    assert_match(/токсин снижает SK и ML цели на 1 до конца боя/, line)
  end

  test "strike summary includes attack roll when not all attacks land" do
    before = {
      entity_id: "spears", name: "Копейщики", armor_type: "medium",
      current_health: 10, models_remaining: 10, skill: 3, melee: 4
    }
    after = before.merge(current_health: 7, models_remaining: 7)
    line = Sim::Battle::ActionResult.text_for(
      actor: { actor_name: "Копейщики", actor_role: "unit", weapon_type: "puncture" },
      action: { type: "melee" },
      before: [ before ],
      after: [ after ],
      damage: 3,
      vector: "front",
      hits_landed: 2,
      attacks_attempted: 3
    )

    assert_match(/попало 2 из 3 атак/, line)
    assert_match(/3 урона/, line)
  end

  test "strike summary includes attack roll for a clean single hit" do
    before = {
      entity_id: "spears", name: "Копейщики", armor_type: "medium",
      current_health: 10, models_remaining: 10
    }
    after = before.merge(current_health: 9, models_remaining: 9)
    line = Sim::Battle::ActionResult.text_for(
      actor: { actor_name: "Копейщики", actor_role: "unit", weapon_type: "puncture" },
      action: { type: "melee" },
      before: [ before ],
      after: [ after ],
      damage: 1,
      vector: "front",
      hits_landed: 1,
      attacks_attempted: 1
    )

    assert_match(/попало 1 из 1 атак/, line)
  end

  test "miss roll text reports zero hits from attempted attacks" do
    line = Sim::Battle::ActionResult.miss_roll_text(
      actor: { actor_name: "Лучники", actor_role: "unit" },
      target_name: "Орки",
      hits_landed: 0,
      attacks_attempted: 2
    )

    assert_equal "Отряд Лучники атакует Орки: попало 0 из 2 атак.", line
  end

  test "strike summary shows total damage from health delta and model health for multi-wound units" do
    before = {
      entity_id: "cannon", name: "Пушка", armor_type: "machine",
      current_health: 8, max_health: 8, model_health: 8, models_remaining: 1
    }
    after = before.merge(current_health: 5, models_remaining: 1)
    line = Sim::Battle::ActionResult.text_for(
      actor: { actor_name: "Генерал", actor_role: "hero", weapon_type: "demolish" },
      action: { type: "shooting" },
      before: [ before ],
      after: [ after ],
      damage: 1,
      vector: "front"
    )

    assert_match(/3 урона/, line)
    assert_match(/осталось 1 моделей, здоровье 5\/8/, line)
  end

  test "remaining models text shows per-model health when one model is left" do
    state = {
      models_remaining: 1,
      model_health: 4,
      current_health: 3,
      max_health: 8
    }

    assert_equal(
      "осталось 1 моделей, здоровье 3/4",
      Sim::Battle::ActionResult.send(:new, actor: {}, action: {}, before: [], after: [], meta: {}).send(:remaining_models_text, state)
    )
  end

  test "toxin after_hit writes a clause instead of a side event" do
    attacker = combatant(abilities: [ "toxin" ])
    defender = combatant(side_index: 1, skill: 4, melee: 5)
    phase = Sim::Battle::Phases::AttackResolution.create_phase("melee", "Фаза боя")
    action = { details: [] }
    Sim::Battle::Rules::Toxin::Melee.after_hit!(
      phase: phase, attacker: attacker, defender: defender, action: action
    )

    assert_empty phase[:events]
    assert_match(/токсин/, action[:clauses].join)
    assert_includes action[:details].join, "toxin"
  end

  test "movement summary lists maneuvers in order without coordinates" do
    line = Sim::Battle::ActionResult.movement_summary(
      actor: { actor_name: "Скелетный блок", actor_role: "unit" },
      motions: [
        { kind: "turn" },
        { kind: "advance" },
        { kind: "wheel" },
        { kind: "advance" }
      ],
      target_name: "Катапульта-камикадзе",
      note: ", обходит Гоблины-лучники"
    )

    assert_equal "Отряд Скелетный блок совершил поворот, затем продвижение, затем колесо, затем продвижение к Катапульта-камикадзе, обходит Гоблины-лучники.", line
  end

  test "movement summary uses hero label" do
    line = Sim::Battle::ActionResult.movement_summary(
      actor: { actor_name: "Шаман", actor_role: "hero" },
      motions: [ { kind: "wheel" }, { kind: "march" } ],
      target_name: "Орки"
    )

    assert_equal "Герой Шаман совершил колесо, затем марш к Орки.", line
  end

  private

  def combatant(**overrides)
    {
      entity_id: "unit-1",
      name: "Unit",
      kind: "unit",
      skill: 3,
      melee: 4,
      abilities: [],
      contributors: { melee: [] }
    }.merge(overrides)
  end
end
