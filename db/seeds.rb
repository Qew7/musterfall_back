abilities = [
  { key: "antiLarge", name: "Anti-Large", category: "combat", description: "Эффективнее против крупных целей." },
  { key: "armorPiercing", name: "Armor Piercing", category: "combat", description: "Лучше пробивает броню." },
  { key: "bannerAura", name: "Banner Aura", category: "aura", description: "Усиливает фронтовой урон прикрепленного отряда." },
  { key: "charge", name: "Charge", category: "combat", description: "Усиливает первый удар в ближнем бою." },
  { key: "disciplined", name: "Disciplined", category: "trait", description: "Лучше держит строй под давлением." },
  { key: "dodge", name: "Dodge", category: "trait", description: "Снижает шанс получить полный урон." },
  { key: "fast", name: "Fast", category: "mobility", description: "Быстрее занимает выгодные позиции." },
  { key: "fear", name: "Fear", category: "trait", description: "Давит мораль и строй противника." },
  { key: "ferocious", name: "Ferocious", category: "trait", description: "Сильнее в затяжной рубке." },
  { key: "flying", name: "Flying", category: "mobility", description: "Летает в пределах MV; садится вне чужих баз; facing свободный; заход в тыл/фланг." },
  { key: "forestborn", name: "Forestborn", category: "trait", description: "Лесные духи игнорируют часть штрафов местности." },
  { key: "leader", name: "Leader", category: "hero", description: "Командир, способный вести армию." },
  { key: "machine", name: "Machine", category: "siege", description: "Осадная машина с усиленным дальним уроном." },
  { key: "monster", name: "Monster", category: "trait", description: "Крупная цель с особой угрозой." },
  { key: "muster", name: "Muster", category: "hero", description: "Позволяет союзным отрядам рядом использовать мораль героя." },
  { key: "poison", name: "Poison", category: "combat", description: "Ослабляет цель после попадания." },
  { key: "precision", name: "Precision", category: "combat", description: "Точнее выбирает важные цели." },
  { key: "ranged", name: "Ranged", category: "combat", description: "Может атаковать на дистанции." },
  { key: "regen", name: "Regeneration", category: "trait", description: "Постепенно восстанавливает здоровье." },
  { key: "shieldwall", name: "Shieldwall", category: "defense", description: "Снижает фронтальный урон." },
  { key: "skirmisher", name: "Skirmisher", category: "mobility", description: "Игнорирует часть штрафов за направление атаки." },
  { key: "steadfast", name: "Steadfast", category: "defense", description: "Лучше держит фронтальную атаку." },
  { key: "steadfastAura", name: "Steadfast Aura", category: "aura", description: "Дарует устойчивость отряду рядом." },
  { key: "undead", name: "Undead", category: "trait", description: "Нежить не знает усталости и паники." },
  { key: "wizard", name: "Wizard", category: "hero", description: "Использует магию в бою." },
  { key: "wizardAura", name: "Wizard Aura", category: "aura", description: "Поддерживает союзников магическим полем." }
]

def normalized_abilities_for(attributes)
  abilities = attributes.fetch(:abilities)
  return abilities if attributes.fetch(:kind) != "hero"

  abilities.include?("muster") ? abilities : [ *abilities, "muster" ]
end

def default_movement_for(attributes)
  abilities = normalized_abilities_for(attributes)
  return 20 if abilities.include?("flying")
  return 7 if attributes.fetch(:mounted) || abilities.include?("fast")
  return 2 if abilities.include?("machine")
  return 4 if abilities.include?("charge") || abilities.include?("skirmisher")

  3
end

def default_base_depth_for(attributes)
  return 2 if attributes.fetch(:mounted)
  return 2 if normalized_abilities_for(attributes).include?("machine")

  1
end

def default_model_class_for(attributes)
  return attributes.fetch(:mounted) ? "cavalry" : "infantry" if attributes.fetch(:kind) == "hero"

  abilities = normalized_abilities_for(attributes)
  return "machine" if abilities.include?("machine")
  return "monster" if abilities.include?("monster")
  return "cavalry" if attributes.fetch(:mounted) || abilities.include?("charge") || abilities.include?("fast")

  "infantry"
end

def default_shooting_range_for(attributes)
  return 0 if attributes.fetch(:ranged).zero?
  abilities = normalized_abilities_for(attributes)
  return 14 if abilities.include?("machine")
  return 11 if abilities.include?("precision")

  9
end

def default_spell_range_for(attributes)
  return 0 if attributes.fetch(:spell).zero?
  return 8 if normalized_abilities_for(attributes).include?("wizard")

  6
end

def default_shooting_template_for(attributes)
  abilities = normalized_abilities_for(attributes)
  return "breath" if attributes.fetch(:weapon_type) == "breath"
  return "blast" if abilities.include?("machine")
  return "volley" if abilities.include?("ranged")

  "single"
end

def default_spell_template_for(attributes)
  return "breath" if attributes.fetch(:weapon_type) == "breath"
  return "blast" if attributes.fetch(:abilities).include?("wizard")

  "single"
end

def default_line_of_sight_for(attributes)
  !normalized_abilities_for(attributes).include?("machine")
end

def default_morale_for(attributes)
  abilities = normalized_abilities_for(attributes)
  return 8 if attributes.fetch(:kind) == "hero"
  return 7 if abilities.include?("disciplined")
  return 7 if abilities.include?("undead")
  return 6 if abilities.include?("fear") || abilities.include?("steadfast")

  5
end

# Cost in hundreds-ish from tier + stats + rules. Rounded to 25.
def computed_template_cost(attributes)
  tier = attributes.fetch(:kind) == "hero" ? "hero" : attributes.fetch(:recruit_tier)
  mult = { "line" => 1.0, "elite" => 1.45, "rare" => 2.1, "hero" => 1.7 }.fetch(tier)
  power = attributes.fetch(:melee) + (attributes.fetch(:ranged) * 1.2) + (attributes.fetch(:spell) * 1.3)
  body = Math.sqrt(attributes.fetch(:models) * attributes.fetch(:model_health))
  ability_factor = 1 + normalized_abilities_for(attributes).size * 0.08
  raw = (4 + power) * body * (attributes.fetch(:skill) / 3.0) * Math.sqrt(attributes.fetch(:attacks)) * ability_factor * mult * 3.5
  ((raw / 25.0).round * 25).clamp(50, 400)
end

factions = [
  {
    slug: "empire",
    name: "Империя",
    vibe: "Дисциплина, артиллерия и штатные маги.",
    passive: "Пехота получает -10% входящего урона спереди.",
    color: "#8a2f1c"
  },
  {
    slug: "greenskins",
    name: "Зеленокожие",
    vibe: "Масса тел, резкие фланговые удары и чудовища.",
    passive: "Каждый первый выигранный фронтовой обмен в бою наносит +1 урон.",
    color: "#375a1a"
  },
  {
    slug: "undead",
    name: "Нежить",
    vibe: "Изнурение, магия и плотные блоки без морали.",
    passive: "В конце каждого хода возвращает 1 здоровье случайному отряду.",
    color: "#4d2f63"
  },
  {
    slug: "wildwood",
    name: "Диколесье",
    vibe: "Стрельба, маневр и живые духи леса.",
    passive: "Скирмишеры игнорируют штрафы от фланга и тыла.",
    color: "#1c5a44"
  },
  {
    slug: "chaos",
    name: "Хаос",
    vibe: "Элитные удары, тяжелая броня и демоническая мощь.",
    passive: "Первый charge каждой тяжелой модели получает +25% силы.",
    color: "#5d1724"
  }
]

templates = [
  # Обычные юниты — 1 атака (монстры / элитные герои — больше)
  { template_key: "state_swords", kind: "unit", recruit_tier: "line", faction_slug: "empire", name: "Имперские мечники", cost: 8, models: 16, model_health: 1, width: 4, armor_type: "medium", weapon_type: "slash", melee: 4, ranged: 0, spell: 0, initiative: 3, abilities: [ "disciplined", "shieldwall" ], skill: 3, mounted: false, attacks: 1 },
  { template_key: "halberdiers", kind: "unit", recruit_tier: "line", faction_slug: "empire", name: "Алебардисты", cost: 7, models: 14, model_health: 1, width: 4, armor_type: "light", weapon_type: "puncture", melee: 5, ranged: 0, spell: 0, initiative: 3, abilities: [ "antiLarge" ], skill: 4, mounted: false, attacks: 1 },
  { template_key: "handgunners", kind: "unit", recruit_tier: "line", faction_slug: "empire", name: "Аркебузиры", cost: 9, models: 10, model_health: 1, width: 5, armor_type: "light", weapon_type: "ranged", melee: 2, ranged: 5, spell: 0, initiative: 4, abilities: [ "ranged", "armorPiercing" ], skill: 3, mounted: false, attacks: 1 },
  { template_key: "outriders", kind: "unit", recruit_tier: "elite", faction_slug: "empire", name: "Аутрайдеры", cost: 10, models: 6, model_health: 1, width: 3, armor_type: "medium", weapon_type: "ranged", melee: 3, ranged: 4, spell: 0, initiative: 4, abilities: [ "ranged", "fast" ], skill: 4, mounted: false, attacks: 1 },
  { template_key: "great_cannon", kind: "unit", recruit_tier: "rare", faction_slug: "empire", name: "Большая пушка", cost: 12, models: 2, model_health: 4, width: 2, armor_type: "machine", weapon_type: "demolish", melee: 2, ranged: 7, spell: 0, initiative: 4, abilities: [ "ranged", "machine" ], skill: 2, mounted: false, attacks: 1 },
  { template_key: "orc_boyz", kind: "unit", recruit_tier: "line", faction_slug: "greenskins", name: "Орки-бойзы", cost: 8, models: 16, model_health: 1, width: 4, armor_type: "medium", weapon_type: "slash", melee: 5, ranged: 0, spell: 0, initiative: 3, abilities: [ "ferocious" ], skill: 3, mounted: false, attacks: 1 },
  { template_key: "goblin_archers", kind: "unit", recruit_tier: "line", faction_slug: "greenskins", name: "Гоблины-лучники", cost: 6, models: 12, model_health: 1, width: 4, armor_type: "light", weapon_type: "ranged", melee: 2, ranged: 4, spell: 0, initiative: 4, abilities: [ "ranged", "skirmisher" ], skill: 2, mounted: false, attacks: 1 },
  { template_key: "boar_riders", kind: "unit", recruit_tier: "elite", faction_slug: "greenskins", name: "Наездники на кабанах", cost: 11, models: 6, model_health: 1, width: 3, armor_type: "heavy", weapon_type: "blunt", melee: 6, ranged: 0, spell: 0, initiative: 3, abilities: [ "charge", "fast" ], skill: 4, mounted: false, attacks: 1 },
  { template_key: "stone_trolls", kind: "unit", recruit_tier: "rare", faction_slug: "greenskins", name: "Каменные тролли", cost: 13, models: 4, model_health: 4, width: 2, armor_type: "heavy", weapon_type: "blunt", melee: 6, ranged: 0, spell: 0, initiative: 3, abilities: [ "monster", "regen" ], skill: 4, mounted: false, attacks: 2 },
  { template_key: "doom_diver", kind: "unit", recruit_tier: "elite", faction_slug: "greenskins", name: "Катапульта-камикадзе", cost: 12, models: 2, model_health: 4, width: 2, armor_type: "machine", weapon_type: "demolish", melee: 1, ranged: 7, spell: 0, initiative: 4, abilities: [ "ranged", "machine" ], skill: 2, mounted: false, attacks: 1 },
  { template_key: "skeleton_block", kind: "unit", recruit_tier: "line", faction_slug: "undead", name: "Скелетный блок", cost: 6, models: 18, model_health: 1, width: 5, armor_type: "light", weapon_type: "slash", melee: 3, ranged: 0, spell: 0, initiative: 3, abilities: [ "undead", "steadfast" ], skill: 2, mounted: false, attacks: 1 },
  { template_key: "grave_guard", kind: "unit", recruit_tier: "elite", faction_slug: "undead", name: "Стража могил", cost: 10, models: 10, model_health: 1, width: 5, armor_type: "heavy", weapon_type: "slash", melee: 5, ranged: 0, spell: 0, initiative: 3, abilities: [ "undead", "armorPiercing" ], skill: 4, mounted: false, attacks: 1 },
  { template_key: "ghoul_pack", kind: "unit", recruit_tier: "line", faction_slug: "undead", name: "Упырская стая", cost: 8, models: 12, model_health: 1, width: 4, armor_type: "light", weapon_type: "puncture", melee: 4, ranged: 0, spell: 0, initiative: 3, abilities: [ "skirmisher", "poison" ], skill: 3, mounted: false, attacks: 1 },
  { template_key: "black_knights", kind: "unit", recruit_tier: "elite", faction_slug: "undead", name: "Черные рыцари", cost: 12, models: 6, model_health: 1, width: 3, armor_type: "heavy", weapon_type: "puncture", melee: 6, ranged: 0, spell: 0, initiative: 3, abilities: [ "charge", "undead", "fast" ], skill: 4, mounted: false, attacks: 1 },
  { template_key: "corpse_cart", kind: "unit", recruit_tier: "elite", faction_slug: "undead", name: "Труповозка", cost: 11, models: 3, model_health: 3, width: 2, armor_type: "magic", weapon_type: "magic", melee: 2, ranged: 4, spell: 0, initiative: 4, abilities: [ "wizardAura", "undead" ], skill: 3, mounted: false, attacks: 1 },
  { template_key: "bone_dragon", kind: "unit", recruit_tier: "rare", faction_slug: "undead", name: "Костяной дракон", cost: 15, models: 1, model_health: 8, width: 2, armor_type: "light", weapon_type: "breath", melee: 3, ranged: 4, spell: 0, initiative: 4, abilities: [ "monster", "flying", "fear", "undead", "ranged" ], skill: 5, mounted: false, attacks: 3 },
  { template_key: "glade_guard", kind: "unit", recruit_tier: "line", faction_slug: "wildwood", name: "Стража поляны", cost: 9, models: 10, model_health: 1, width: 5, armor_type: "light", weapon_type: "ranged", melee: 2, ranged: 5, spell: 0, initiative: 4, abilities: [ "ranged", "precision" ], skill: 4, mounted: false, attacks: 1 },
  { template_key: "wardancers", kind: "unit", recruit_tier: "line", faction_slug: "wildwood", name: "Танцоры войны", cost: 9, models: 8, model_health: 1, width: 4, armor_type: "light", weapon_type: "slash", melee: 5, ranged: 0, spell: 0, initiative: 3, abilities: [ "skirmisher", "dodge" ], skill: 4, mounted: false, attacks: 1 },
  { template_key: "dryad_grove", kind: "unit", recruit_tier: "elite", faction_slug: "wildwood", name: "Стайка дриад", cost: 10, models: 8, model_health: 2, width: 4, armor_type: "magic", weapon_type: "slash", melee: 4, ranged: 0, spell: 0, initiative: 3, abilities: [ "fear", "forestborn" ], skill: 3, mounted: false, attacks: 1 },
  { template_key: "stag_knights", kind: "unit", recruit_tier: "elite", faction_slug: "wildwood", name: "Рыцари на оленях", cost: 12, models: 6, model_health: 1, width: 3, armor_type: "medium", weapon_type: "puncture", melee: 6, ranged: 0, spell: 0, initiative: 3, abilities: [ "charge", "fast" ], skill: 4, mounted: false, attacks: 1 },
  { template_key: "treeman", kind: "unit", recruit_tier: "rare", faction_slug: "wildwood", name: "Древочеловек", cost: 14, models: 3, model_health: 4, width: 2, armor_type: "heavy", weapon_type: "blunt", melee: 6, ranged: 2, spell: 0, initiative: 4, abilities: [ "monster", "fear" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "grove_hawk", kind: "unit", recruit_tier: "rare", faction_slug: "wildwood", name: "Великий ястреб рощи", cost: 12, models: 1, model_health: 5, width: 2, armor_type: "medium", weapon_type: "puncture", melee: 5, ranged: 0, spell: 0, initiative: 5, abilities: [ "monster", "flying", "fast", "forestborn" ], skill: 4, mounted: false, attacks: 2 },
  { template_key: "chaos_warriors", kind: "unit", recruit_tier: "elite", faction_slug: "chaos", name: "Воины Хаоса", cost: 11, models: 12, model_health: 1, width: 4, armor_type: "heavy", weapon_type: "slash", melee: 6, ranged: 0, spell: 0, initiative: 3, abilities: [ "disciplined", "fear" ], skill: 5, mounted: false, attacks: 1 },
  { template_key: "marauders", kind: "unit", recruit_tier: "line", faction_slug: "chaos", name: "Мародеры", cost: 7, models: 14, model_health: 1, width: 4, armor_type: "medium", weapon_type: "slash", melee: 4, ranged: 0, spell: 0, initiative: 3, abilities: [ "ferocious" ], skill: 3, mounted: false, attacks: 1 },
  { template_key: "chaos_knights", kind: "unit", recruit_tier: "elite", faction_slug: "chaos", name: "Рыцари Хаоса", cost: 13, models: 6, model_health: 1, width: 3, armor_type: "heavy", weapon_type: "puncture", melee: 7, ranged: 0, spell: 0, initiative: 3, abilities: [ "charge", "fast" ], skill: 5, mounted: false, attacks: 1 },
  { template_key: "chaos_spawn", kind: "unit", recruit_tier: "elite", faction_slug: "chaos", name: "Отродье Хаоса", cost: 12, models: 4, model_health: 3, width: 2, armor_type: "magic", weapon_type: "blunt", melee: 5, ranged: 0, spell: 0, initiative: 3, abilities: [ "monster", "fear", "regen" ], skill: 4, mounted: false, attacks: 2 },
  { template_key: "hellcannon", kind: "unit", recruit_tier: "rare", faction_slug: "chaos", name: "Адская пушка", cost: 14, models: 2, model_health: 4, width: 2, armor_type: "machine", weapon_type: "demolish", melee: 2, ranged: 8, spell: 0, initiative: 4, abilities: [ "ranged", "machine", "fear" ], skill: 2, mounted: false, attacks: 1 },
  { template_key: "captain_general", kind: "hero", recruit_tier: "line", faction_slug: "empire", name: "Генерал Империи", cost: 12, models: 1, model_health: 3, width: 1, armor_type: "heavy", weapon_type: "slash", melee: 4, ranged: 0, spell: 0, initiative: 5, abilities: [ "leader" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "battle_wizard", kind: "hero", recruit_tier: "line", faction_slug: "empire", name: "Боевой маг", cost: 14, models: 1, model_health: 2, width: 1, armor_type: "magic", weapon_type: "magic", melee: 2, ranged: 4, spell: 5, initiative: 5, abilities: [ "wizard", "leader" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "griffon_marshal", kind: "hero", recruit_tier: "line", faction_slug: "empire", name: "Маршал на грифоне", cost: 14, models: 1, model_health: 4, width: 1, armor_type: "heavy", weapon_type: "puncture", melee: 5, ranged: 1, spell: 0, initiative: 5, abilities: [ "leader", "monster", "flying" ], skill: 5, mounted: true, attacks: 3 },
  { template_key: "warboss", kind: "hero", recruit_tier: "line", faction_slug: "greenskins", name: "Варбосс", cost: 12, models: 1, model_health: 4, width: 1, armor_type: "heavy", weapon_type: "slash", melee: 5, ranged: 0, spell: 0, initiative: 5, abilities: [ "leader", "ferocious" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "shaman", kind: "hero", recruit_tier: "line", faction_slug: "greenskins", name: "Шаман", cost: 14, models: 1, model_health: 2, width: 1, armor_type: "magic", weapon_type: "magic", melee: 2, ranged: 4, spell: 5, initiative: 5, abilities: [ "wizard" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "boar_chief", kind: "hero", recruit_tier: "line", faction_slug: "greenskins", name: "Вождь на кабане", cost: 14, models: 1, model_health: 3, width: 1, armor_type: "heavy", weapon_type: "blunt", melee: 5, ranged: 0, spell: 0, initiative: 5, abilities: [ "leader", "charge" ], skill: 5, mounted: true, attacks: 2 },
  { template_key: "vampire_lord", kind: "hero", recruit_tier: "line", faction_slug: "undead", name: "Лорд-вампир", cost: 12, models: 1, model_health: 4, width: 1, armor_type: "heavy", weapon_type: "slash", melee: 5, ranged: 3, spell: 4, initiative: 5, abilities: [ "wizard", "leader", "regen" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "necromancer", kind: "hero", recruit_tier: "line", faction_slug: "undead", name: "Некромант", cost: 14, models: 1, model_health: 2, width: 1, armor_type: "magic", weapon_type: "magic", melee: 1, ranged: 5, spell: 5, initiative: 5, abilities: [ "wizard" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "wight_king", kind: "hero", recruit_tier: "line", faction_slug: "undead", name: "Король-лич", cost: 12, models: 1, model_health: 3, width: 1, armor_type: "heavy", weapon_type: "puncture", melee: 4, ranged: 0, spell: 0, initiative: 5, abilities: [ "leader", "undead" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "waystalker", kind: "hero", recruit_tier: "line", faction_slug: "wildwood", name: "Вэйстокер", cost: 14, models: 1, model_health: 2, width: 1, armor_type: "light", weapon_type: "ranged", melee: 2, ranged: 5, spell: 0, initiative: 5, abilities: [ "leader", "ranged" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "spellweaver", kind: "hero", recruit_tier: "line", faction_slug: "wildwood", name: "Спеллвивер", cost: 14, models: 1, model_health: 2, width: 1, armor_type: "magic", weapon_type: "magic", melee: 2, ranged: 5, spell: 5, initiative: 5, abilities: [ "wizard" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "stag_prince", kind: "hero", recruit_tier: "line", faction_slug: "wildwood", name: "Принц на великом олене", cost: 14, models: 1, model_health: 3, width: 1, armor_type: "medium", weapon_type: "puncture", melee: 5, ranged: 1, spell: 0, initiative: 5, abilities: [ "leader", "charge" ], skill: 5, mounted: true, attacks: 2 },
  { template_key: "chaos_lord", kind: "hero", recruit_tier: "line", faction_slug: "chaos", name: "Лорд Хаоса", cost: 12, models: 1, model_health: 4, width: 1, armor_type: "heavy", weapon_type: "slash", melee: 6, ranged: 0, spell: 0, initiative: 5, abilities: [ "leader", "fear" ], skill: 6, mounted: false, attacks: 2 },
  { template_key: "sorcerer", kind: "hero", recruit_tier: "line", faction_slug: "chaos", name: "Чародей Хаоса", cost: 14, models: 1, model_health: 2, width: 1, armor_type: "magic", weapon_type: "magic", melee: 2, ranged: 5, spell: 5, initiative: 5, abilities: [ "wizard" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "daemon_prince", kind: "hero", recruit_tier: "line", faction_slug: "chaos", name: "Демонический принц", cost: 14, models: 1, model_health: 5, width: 1, armor_type: "magic", weapon_type: "magic", melee: 5, ranged: 3, spell: 5, initiative: 5, abilities: [ "leader", "monster", "wizard", "flying" ], skill: 6, mounted: true, attacks: 3 }
]

templates.map! { |attributes| attributes.merge(cost: computed_template_cost(attributes)) }

upgrades = [
  { upgrade_key: "rune_blade", name: "Рунный клинок", category: "weapon", summary: "Melee +2, тип оружия slash." },
  { upgrade_key: "meteor_hammer", name: "Молот кометы", category: "weapon", summary: "Melee +2, blunt лучше пробивает heavy." },
  { upgrade_key: "dragonspear", name: "Драконье копье", category: "weapon", summary: "Melee +1, puncture и antiLarge." },
  { upgrade_key: "gilded_plate", name: "Позолоченный доспех", category: "armor", summary: "Armor heavy и +1 здоровье." },
  { upgrade_key: "shadow_cloak", name: "Плащ теней", category: "trait", summary: "Получает skirmisher и dodge." },
  { upgrade_key: "war_banner", name: "Знамя войны", category: "trait", summary: "Если герой в отряде, тот бьет сильнее на фронт." },
  { upgrade_key: "arcane_focus", name: "Тайный фокус", category: "ability", summary: "Spell power +2." },
  { upgrade_key: "gryphon_hide", name: "Шкура грифона", category: "armor", summary: "Armor magic и regen." },
  { upgrade_key: "longbow_mastery", name: "Мастер длинного лука", category: "ability", summary: "Ranged +2 и precision." },
  { upgrade_key: "veteran_drill", name: "Ветеранская выучка", category: "trait", summary: "Здоровье +1 и melee +1." },
  { upgrade_key: "battle_prayer", name: "Боевая молитва", category: "ability", summary: "Поддерживаемый отряд получает steadfast." },
  { upgrade_key: "hellfire_breath", name: "Адское дыхание", category: "ability", summary: "Ranged становится breath и +2." }
]

factions.each_with_index do |attributes, index|
  faction = Faction.find_or_initialize_by(slug: attributes.fetch(:slug))
  faction.update!(attributes.merge(position: index))
end

templates.each do |attributes|
  faction = Faction.find_by!(slug: attributes.fetch(:faction_slug))
  ArmyTemplate.find_or_initialize_by(template_key: attributes.fetch(:template_key)).update!(
    attributes.except(:faction_slug).merge(
      abilities: normalized_abilities_for(attributes),
      model_class: attributes[:model_class] || default_model_class_for(attributes),
      model_base_width: attributes[:model_base_width],
      model_base_depth: attributes[:model_base_depth],
      base_depth: attributes[:base_depth] || default_base_depth_for(attributes),
      movement: attributes[:movement] || default_movement_for(attributes),
      morale: attributes[:morale] || default_morale_for(attributes),
      shooting_range: attributes[:shooting_range] || default_shooting_range_for(attributes),
      spell_range: attributes[:spell_range] || default_spell_range_for(attributes),
      shooting_template: attributes[:shooting_template] || default_shooting_template_for(attributes),
      spell_template: attributes[:spell_template] || default_spell_template_for(attributes),
      requires_line_of_sight: attributes.key?(:requires_line_of_sight) ? attributes[:requires_line_of_sight] : default_line_of_sight_for(attributes),
      faction: faction
    )
  )
end

upgrades.each_with_index do |attributes, index|
  HeroUpgrade.find_or_initialize_by(upgrade_key: attributes.fetch(:upgrade_key)).update!(attributes.merge(position: index))
end

abilities.each do |attributes|
  Ability.find_or_initialize_by(key: attributes.fetch(:key)).update!(attributes)
end

ArmyTemplate.find_each do |template|
  template.army_template_abilities.delete_all
  template.abilities.each do |ability_key|
    template.army_template_abilities.create!(ability: Ability.find_by!(key: ability_key))
  end
end
# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
