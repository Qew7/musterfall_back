abilities = [
  { key: "antiLarge", name: "Anti-Large", category: "combat", description: "В ближнем бою наносит ×1.35 урона целям класса monster и cavalry." },
  { key: "armorPiercing", name: "Armor Piercing", category: "combat", description: "Вдвое уменьшает штраф (и бонус) брони цели к урону." },
  { key: "bannerAura", name: "Banner Aura", category: "aura", description: "Если герой встроен в отряд, ML отряда +1." },
  { key: "disciplined", name: "Disciplined", category: "trait", description: "Порог проверки морали +1." },
  { key: "boarCharge", name: "Кабаний обход", category: "combat", description: "Фланговый или тыловой заряд: союзник с Ferocious в той же рубке получает +1 SK на этот раунд." },
  { key: "corpseTrail", name: "Поднятие мёртвых", category: "combat", description: "Попадание призывает отряд поднятых мертвецов на свободном месте рядом с целью; смотрят на ближайшего врага." },
  { key: "dodge", name: "Dodge", category: "trait", description: "Шанс попадания по этому отряду ×0.8." },
  { key: "slingCatapult", name: "Катапульта-камикадзе", category: "siege", description: "Перед выстрелом тратит 1 модель союзных расходников в 6″. Тогда атака идёт взрывным шаблоном. Без расходника — обычный выстрел." },
  { key: "fast", name: "Fast", category: "mobility", description: "Кавалерийский профиль: MV 7, база cavalry." },
  { key: "fear", name: "Fear", category: "trait", description: "Проверки страха только при заряде в контакт: не-fear vs fear — атакующий, провал — стоп на полпути; fear vs не-fear — защитник, провал — не бьёт в раунде. Уже в рубке — без проверок. −1 к порогу морали врагов рядом." },
  { key: "fearless", name: "Иммунитет к страху", category: "trait", description: "Не проходит проверки страха и не даёт штраф страха. Сам не устрашает." },
  { key: "ferocious", name: "Ferocious", category: "trait", description: "Каждый следующий раунд той же рубки: SK +1, максимум 6. Сброс, если вышел из контакта." },
  { key: "flying", name: "Flying", category: "mobility", description: "Летает на полный MV; садится вне чужих баз; facing свободный; может заходить во фланг и тыл." },
  { key: "forestborn", name: "Forestborn", category: "trait", description: "Не получает штраф стрельбы по цели в лесу. Стрелок стремится занять лес." },
  { key: "wildborn", name: "Wildborn", category: "trait", description: "В лесу: иммунитет к страху. Может зарядить врага в чаще, даже если сам вне леса." },
  { key: "forestkin", name: "Forestkin", category: "trait", description: "Ближний бой оставляет лес на месте удара (если его там нет). В лесу регенерирует 1 здоровье за раунд." },
  { key: "slingFodder", name: "Гоблин", category: "trait", description: "Модель может быть израсходована Катапультой-камикадзе в 6″." },
  { key: "leader", name: "Leader", category: "hero", description: "Герой может быть генералом армии." },
  { key: "machine", name: "Machine", category: "siege", description: "Осадная машина: дальний урон ×1.25, дальность 16″, шаблон blast, MV 2." },
  { key: "antiFlying", name: "Противовоздушная", category: "siege", description: "Осадная стрельба по летунам: урон ×0.5." },
  { key: "heavyBlast", name: "Тяжёлый снаряд", category: "siege", description: "Взрывной шаблон с радиусом ×1.5." },
  { key: "monster", name: "Monster", category: "trait", description: "Класс модели monster. Получает дополнительный урон от Anti-Large." },
  { key: "momentumCharge", name: "Удар с хода", category: "combat", description: "Заряд: урон ближнего боя +5% за каждый пройденный дюйм, максимум +50%." },
  { key: "muster", name: "Muster", category: "hero", description: "Союзный отряд в пределах MO героя может использовать MO героя, если оно выше своего." },
  { key: "outrider", name: "Конный стрелок", category: "mobility", description: "Не идёт в рукопашную. Держится на дистанции стрельбы и стреляет после движения." },
  { key: "poison", name: "Poison", category: "combat", description: "После попадания в ближнем бою убивает одну целую модель с model_health > 1, если сам удар не снял модель целиком. На 1W-цели не действует. Не действует на Undead." },
  { key: "precision", name: "Precision", category: "combat", description: "Дальность стрельбы 11″ вместо 9″." },
  { key: "ranged", name: "Ranged", category: "combat", description: "Может атаковать в фазе стрельбы. Шаблон по умолчанию — volley." },
  { key: "regen", name: "Regeneration", category: "trait", description: "В конце раунда восстанавливает 1 здоровье, если отряд жив и ранен." },
  { key: "lavaSpit", name: "Лавовый харчок", category: "combat", description: "В конце раунда, до белого флага: каждая модель бьёт в рубке ещё раз; плоский урон от melee, без бонуса стороны/заряда и без учёта брони и щитовых правил." },
  { key: "shieldwall", name: "Shieldwall", category: "defense", description: "Фронтальный заряд по этому отряду: урон ×0.75." },
  { key: "skirmisher", name: "Skirmisher", category: "mobility", description: "Нет штрафа за фланг/тыл. Стрельба не требует фронтальной дуги." },
  { key: "resolute", name: "Resolute", category: "defense", description: "Если отряд проигрывает рукопашную, порог морали +2. У нежити — только пока генерал жив." },
  { key: "resoluteAura", name: "Resolute Aura", category: "aura", description: "Встроенный отряд получает Resolute." },
  { key: "supportRank", name: "Древковое оружие", category: "combat", description: "При фронтальном контакте бьёт второй ряд: до 2× файлов, не больше оставшихся моделей." },
  { key: "throwRocks", name: "Камнемёт", category: "combat", description: "Не идёт в рукопашную. Сближается, пока цель не окажется в дальности броска камней." },
  { key: "toxin", name: "Toxin", category: "combat", description: "Первое попадание (ближний бой или выстрел) снижает SK и ML цели на 1 до конца боя. Один раз на цель." },
  { key: "undead", name: "Undead", category: "trait", description: "Провал морали: отряд рассыпается (герой теряет здоровье по разнице), вместо бегства. Иммунен к яду. Не марширует." },
  { key: "runeArmor", name: "Рунические доспехи", category: "defense", description: "Входящий немагический урон ×⅔." },
  { key: "wizard", name: "Wizard", category: "hero", description: "Колдует в фазе магии. Дальность заклинаний 8″." },
  { key: "wizardAura", name: "Wizard Aura", category: "aura", description: "Нет отдельного боевого эффекта." }
]

def normalized_abilities_for(attributes)
  abilities = attributes.fetch(:abilities)
  return abilities if attributes.fetch(:kind) != "hero"

  abilities.include?("muster") ? abilities : [ *abilities, "muster" ]
end

# ponytail: model_health >= 4 marks bulky non-siege units as monster; heroes stay manual.
def apply_monster_trait!(attributes)
  abilities = normalized_abilities_for(attributes)
  return attributes if abilities.include?("monster") || abilities.include?("machine")
  return attributes unless attributes.fetch(:kind) == "unit"
  return attributes if attributes.fetch(:model_health) < 4

  attributes.merge(abilities: [ *abilities, "monster" ])
end

def default_movement_for(attributes)
  abilities = normalized_abilities_for(attributes)
  return 20 if abilities.include?("flying")
  return 7 if attributes.fetch(:mounted) || abilities.include?("fast")
  return 2 if abilities.include?("machine")
  return 4 if abilities.include?("skirmisher")

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
  return "cavalry" if attributes.fetch(:mounted) || abilities.include?("fast")

  "infantry"
end

def default_shooting_range_for(attributes)
  return 0 if attributes.fetch(:ranged).zero?
  abilities = normalized_abilities_for(attributes)
  return 16 if abilities.include?("machine")
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
  return 6 if abilities.include?("fear") || abilities.include?("resolute")

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
    vibe: "Строй, древковое оружие, мобильная стрельба и артиллерия.",
    passive: "Щиты встречают фронтальный натиск, а алебарды бьют из второго ряда.",
    color: "#8a2f1c"
  },
  {
    slug: "greenskins",
    name: "Зеленокожие",
    vibe: "Масса тел, резкие фланговые удары и чудовища.",
    passive: "Свирепые орки набирают мастерство в затяжной рубке.",
    color: "#375a1a"
  },
  {
    slug: "undead",
    name: "Нежить",
    vibe: "Изнурение, магия и плотные блоки без морали.",
    passive: "Нежить не бежит: павшие отряды рассыпаются. Пока генерал жив, одно раненое подразделение нежити восстанавливает 1 здоровье за раунд, а скелетный блок держит строй (Resolute).",
    color: "#4d2f63"
  },
  {
    slug: "wildwood",
    name: "Диколесье",
    vibe: "Стрельба, маневр и живые духи леса.",
    passive: "Дикие воины сильнее в чаще; духи рощи прорастают там, где бьют.",
    color: "#1c5a44"
  },
  {
    slug: "chaos",
    name: "Хаос",
    vibe: "Элитные удары, тяжелая броня и демоническая мощь.",
    passive: "Руническая элита выдерживает обычное оружие, а мутации непредсказуемы.",
    color: "#5d1724"
  }
]

templates = [
  # ── Империя (empire) ───────────────────────────────────────
  # line
  { template_key: "state_swords", kind: "unit", recruit_tier: "line", faction_slug: "empire", name: "Имперские мечники", cost: 8, models: 14, model_health: 1, width: 4, armor_type: "medium", weapon_type: "slash", melee: 4, ranged: 0, spell: 0, initiative: 3, abilities: [ "shieldwall" ], skill: 3, mounted: false, attacks: 1 },
  { template_key: "halberdiers", kind: "unit", recruit_tier: "line", faction_slug: "empire", name: "Алебардисты", cost: 200, models: 14, model_health: 1, width: 4, armor_type: "light", weapon_type: "puncture", melee: 4, ranged: 0, spell: 0, initiative: 3, abilities: [ "antiLarge", "supportRank" ], skill: 4, mounted: false, attacks: 1 },
  { template_key: "handgunners", kind: "unit", recruit_tier: "line", faction_slug: "empire", name: "Аркебузиры", cost: 9, models: 10, model_health: 1, width: 5, armor_type: "light", weapon_type: "ranged", melee: 3, ranged: 5, spell: 0, initiative: 4, abilities: [ "ranged", "armorPiercing" ], skill: 3, mounted: false, attacks: 1 },
  # elite
  { template_key: "outriders", kind: "unit", recruit_tier: "elite", faction_slug: "empire", name: "Аутрайдеры", cost: 225, models: 6, model_health: 2, width: 3, armor_type: "medium", weapon_type: "ranged", melee: 3, ranged: 5, spell: 0, initiative: 4, abilities: [ "ranged", "fast", "outrider" ], skill: 4, mounted: true, attacks: 1, shooting_range: 10, shooting_template: "common" },
  # rare
  { template_key: "great_cannon", kind: "unit", recruit_tier: "rare", faction_slug: "empire", name: "Большая пушка", cost: 225, models: 1, model_health: 10, width: 2, armor_type: "machine", weapon_type: "demolish", melee: 2, ranged: 7, spell: 0, initiative: 4, abilities: [ "ranged", "machine", "heavyBlast" ], skill: 2, mounted: false, attacks: 1, shooting_range: 10 },
  { template_key: "sky_lancers", kind: "unit", recruit_tier: "rare", faction_slug: "empire", name: "Небесные копейщики", cost: 15, models: 6, model_health: 2, width: 3, armor_type: "heavy", weapon_type: "puncture", melee: 6, ranged: 0, spell: 0, initiative: 5, abilities: [ "flying", "momentumCharge" ], skill: 5, mounted: true, attacks: 1 },
  # heroes
  { template_key: "captain_general", kind: "hero", recruit_tier: "line", faction_slug: "empire", name: "Генерал Империи", cost: 12, models: 1, model_health: 3, width: 1, armor_type: "heavy", weapon_type: "slash", melee: 4, ranged: 0, spell: 0, initiative: 5, abilities: [ "leader" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "battle_wizard", kind: "hero", recruit_tier: "line", faction_slug: "empire", name: "Боевой маг", cost: 14, models: 1, model_health: 2, width: 1, armor_type: "magic", weapon_type: "magic", melee: 2, ranged: 4, spell: 5, initiative: 5, abilities: [ "wizard", "leader" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "engineer_captain", kind: "hero", recruit_tier: "line", faction_slug: "empire", name: "Инженер-капитан", cost: 13, models: 1, model_health: 2, width: 1, armor_type: "light", weapon_type: "ranged", melee: 2, ranged: 5, spell: 0, initiative: 5, abilities: [ "ranged", "armorPiercing" ], skill: 4, mounted: false, attacks: 2, shooting_range: 10 },

  # ── Зеленокожие (greenskins) ───────────────────────────────
  # line
  { template_key: "orc_brutes", kind: "unit", recruit_tier: "line", faction_slug: "greenskins", name: "Орки-громилы", cost: 8, models: 14, model_health: 1, width: 4, armor_type: "medium", weapon_type: "slash", melee: 4, ranged: 0, spell: 0, initiative: 3, abilities: [ "ferocious" ], skill: 3, mounted: false, attacks: 1 },
  { template_key: "goblin_archers", kind: "unit", recruit_tier: "line", faction_slug: "greenskins", name: "Гоблины-лучники", cost: 55, models: 15, model_health: 1, width: 5, armor_type: "light", weapon_type: "ranged", melee: 2, ranged: 3, spell: 0, initiative: 4, abilities: [ "ranged", "skirmisher", "slingFodder" ], skill: 2, mounted: false, attacks: 1, shooting_template: "common" },
  # elite
  { template_key: "boar_riders", kind: "unit", recruit_tier: "elite", faction_slug: "greenskins", name: "Наездники на кабанах", cost: 11, models: 6, model_health: 1, width: 3, armor_type: "heavy", weapon_type: "blunt", melee: 6, ranged: 0, spell: 0, initiative: 3, abilities: [ "fast", "boarCharge", "momentumCharge" ], skill: 4, mounted: false, attacks: 1 },
  { template_key: "sling_catapult", kind: "unit", recruit_tier: "elite", faction_slug: "greenskins", name: "Катапульта-камикадзе", cost: 12, models: 1, model_health: 8, width: 2, armor_type: "machine", weapon_type: "demolish", melee: 1, ranged: 7, spell: 0, initiative: 4, abilities: [ "ranged", "machine", "slingCatapult" ], skill: 2, mounted: false, attacks: 1, shooting_template: "single" },
  # rare
  { template_key: "stone_trolls", kind: "unit", recruit_tier: "rare", faction_slug: "greenskins", name: "Каменные тролли", cost: 13, models: 3, model_health: 6, width: 3, armor_type: "heavy", weapon_type: "blunt", melee: 6, ranged: 0, spell: 0, initiative: 3, abilities: [ "regen", "lavaSpit" ], skill: 4, mounted: false, attacks: 2 },
  # heroes
  { template_key: "war_chief", kind: "hero", recruit_tier: "line", faction_slug: "greenskins", name: "Вождь орды", cost: 12, models: 1, model_health: 4, width: 1, armor_type: "heavy", weapon_type: "slash", melee: 5, ranged: 0, spell: 0, initiative: 5, abilities: [ "leader", "ferocious" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "shaman", kind: "hero", recruit_tier: "line", faction_slug: "greenskins", name: "Шаман", cost: 14, models: 1, model_health: 2, width: 1, armor_type: "magic", weapon_type: "magic", melee: 2, ranged: 4, spell: 5, initiative: 5, abilities: [ "wizard" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "iron_maw", kind: "hero", recruit_tier: "line", faction_slug: "greenskins", name: "Железная челюсть", cost: 13, models: 1, model_health: 5, width: 1, armor_type: "heavy", weapon_type: "blunt", melee: 6, ranged: 0, spell: 0, initiative: 4, abilities: [ "ferocious", "regen" ], skill: 4, mounted: false, attacks: 2 },

  # ── Нежить (undead) ────────────────────────────────────────
  # line
  { template_key: "skeleton_block", kind: "unit", recruit_tier: "line", faction_slug: "undead", name: "Скелетный блок", cost: 6, models: 15, model_health: 1, width: 5, armor_type: "light", weapon_type: "slash", melee: 3, ranged: 0, spell: 0, initiative: 3, abilities: [ "undead", "fear", "resolute" ], skill: 3, mounted: false, attacks: 1 },
  { template_key: "ghoul_pack", kind: "unit", recruit_tier: "line", faction_slug: "undead", name: "Упырская стая", cost: 125, models: 12, model_health: 1, width: 4, armor_type: "light", weapon_type: "puncture", melee: 3, ranged: 0, spell: 0, initiative: 3, abilities: [ "fear", "skirmisher", "poison" ], skill: 3, mounted: false, attacks: 1 },
  # elite
  { template_key: "crypt_guard", kind: "unit", recruit_tier: "elite", faction_slug: "undead", name: "Криптовая стража", cost: 10, models: 10, model_health: 1, width: 5, armor_type: "heavy", weapon_type: "slash", melee: 5, ranged: 0, spell: 0, initiative: 3, abilities: [ "undead", "fear", "armorPiercing" ], skill: 4, mounted: false, attacks: 1 },
  { template_key: "shadow_riders", kind: "unit", recruit_tier: "elite", faction_slug: "undead", name: "Теневые всадники", cost: 12, models: 6, model_health: 1, width: 3, armor_type: "heavy", weapon_type: "puncture", melee: 6, ranged: 0, spell: 0, initiative: 3, abilities: [ "fear", "fast", "momentumCharge" ], skill: 4, mounted: false, attacks: 1 },
  { template_key: "corpse_cart", kind: "unit", recruit_tier: "elite", faction_slug: "undead", name: "Труповозка", cost: 11, models: 1, model_health: 9, width: 2, base_depth: 2, model_class: "machine", armor_type: "magic", weapon_type: "magic", melee: 2, ranged: 4, spell: 0, initiative: 4, abilities: [ "ranged", "machine", "corpseTrail", "undead", "fear" ], skill: 3, mounted: false, attacks: 1 },
  # rare
  { template_key: "bone_dragon", kind: "unit", recruit_tier: "rare", faction_slug: "undead", name: "Костяной дракон", cost: 15, models: 1, model_health: 6, width: 2, armor_type: "light", weapon_type: "breath", melee: 3, ranged: 4, spell: 0, initiative: 4, abilities: [ "flying", "fear", "undead", "ranged" ], skill: 5, mounted: false, attacks: 2 },
  # heroes
  { template_key: "night_lord", kind: "hero", recruit_tier: "line", faction_slug: "undead", name: "Ночной лорд", cost: 12, models: 1, model_health: 4, width: 1, armor_type: "heavy", weapon_type: "slash", melee: 5, ranged: 3, spell: 4, initiative: 5, abilities: [ "wizard", "leader", "regen" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "necromancer", kind: "hero", recruit_tier: "line", faction_slug: "undead", name: "Некромант", cost: 14, models: 1, model_health: 2, width: 1, armor_type: "magic", weapon_type: "magic", melee: 1, ranged: 5, spell: 5, initiative: 5, abilities: [ "wizard" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "barrow_king", kind: "hero", recruit_tier: "line", faction_slug: "undead", name: "Король курганов", cost: 12, models: 1, model_health: 3, width: 1, armor_type: "heavy", weapon_type: "puncture", melee: 4, ranged: 0, spell: 0, initiative: 5, abilities: [ "leader", "undead" ], skill: 5, mounted: false, attacks: 2 },

  # ── Диколесье (wildwood) ───────────────────────────────────
  # line
  { template_key: "grove_archers", kind: "unit", recruit_tier: "line", faction_slug: "wildwood", name: "Стража поляны", cost: 175, models: 10, model_health: 1, width: 5, armor_type: "light", weapon_type: "ranged", melee: 2, ranged: 4, spell: 0, initiative: 4, abilities: [ "ranged", "precision", "forestborn", "wildborn" ], skill: 4, mounted: false, attacks: 1, shooting_template: "common" },
  { template_key: "war_dancers", kind: "unit", recruit_tier: "line", faction_slug: "wildwood", name: "Танцоры войны", cost: 9, models: 10, model_health: 1, width: 5, armor_type: "light", weapon_type: "slash", melee: 5, ranged: 0, spell: 0, initiative: 3, abilities: [ "skirmisher", "dodge", "wildborn" ], skill: 4, mounted: false, attacks: 1 },
  # elite
  { template_key: "dryad_grove", kind: "unit", recruit_tier: "elite", faction_slug: "wildwood", name: "Стайка дриад", cost: 10, models: 8, model_health: 2, width: 4, armor_type: "magic", weapon_type: "slash", melee: 4, ranged: 0, spell: 0, initiative: 3, abilities: [ "fear", "forestkin" ], skill: 3, mounted: false, attacks: 1 },
  { template_key: "stag_knights", kind: "unit", recruit_tier: "elite", faction_slug: "wildwood", name: "Рыцари на оленях", cost: 12, models: 6, model_health: 1, width: 3, armor_type: "medium", weapon_type: "puncture", melee: 6, ranged: 0, spell: 0, initiative: 3, abilities: [ "fast", "fearless", "momentumCharge", "wildborn" ], skill: 4, mounted: false, attacks: 1 },
  # rare
  { template_key: "treeman", kind: "unit", recruit_tier: "rare", faction_slug: "wildwood", name: "Древочеловек", cost: 14, models: 3, model_health: 4, width: 3, armor_type: "heavy", weapon_type: "blunt", melee: 5, ranged: 2, spell: 0, initiative: 4, abilities: [ "fear", "ranged", "throwRocks", "forestkin" ], skill: 5, mounted: false, attacks: 2, shooting_range: 8 },
  { template_key: "grove_hawk", kind: "unit", recruit_tier: "rare", faction_slug: "wildwood", name: "Великий ястреб рощи", cost: 12, models: 1, model_health: 5, width: 2, armor_type: "medium", weapon_type: "puncture", melee: 5, ranged: 0, spell: 0, initiative: 5, abilities: [ "flying", "fast", "forestborn", "wildborn" ], skill: 4, mounted: false, attacks: 2 },
  # heroes
  { template_key: "path_stalker", kind: "hero", recruit_tier: "line", faction_slug: "wildwood", name: "Следопыт", cost: 14, models: 1, model_health: 2, width: 1, armor_type: "light", weapon_type: "ranged", melee: 2, ranged: 5, spell: 0, initiative: 5, abilities: [ "leader", "ranged", "wildborn" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "grove_weaver", kind: "hero", recruit_tier: "line", faction_slug: "wildwood", name: "Лесной чародей", cost: 14, models: 1, model_health: 2, width: 1, armor_type: "magic", weapon_type: "magic", melee: 2, ranged: 5, spell: 5, initiative: 5, abilities: [ "wizard", "wildborn" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "forest_warden", kind: "hero", recruit_tier: "line", faction_slug: "wildwood", name: "Лесной страж", cost: 13, models: 1, model_health: 3, width: 1, armor_type: "medium", weapon_type: "slash", melee: 5, ranged: 0, spell: 0, initiative: 5, abilities: [ "wildborn", "forestkin", "skirmisher" ], skill: 5, mounted: false, attacks: 2 },

  # ── Хаос (chaos) ───────────────────────────────────────────
  # line
  { template_key: "reaver_band", kind: "unit", recruit_tier: "line", faction_slug: "chaos", name: "Отряд грабителей", cost: 7, models: 10, model_health: 1, width: 5, armor_type: "medium", weapon_type: "slash", melee: 4, ranged: 0, spell: 0, initiative: 3, abilities: [], skill: 3, mounted: false, attacks: 1 },
  # elite
  { template_key: "rift_heavies", kind: "unit", recruit_tier: "elite", faction_slug: "chaos", name: "Тяжёлая гвардия", cost: 11, models: 10, model_health: 1, width: 5, armor_type: "heavy", weapon_type: "slash", melee: 3, ranged: 0, spell: 0, initiative: 3, abilities: [ "disciplined", "fearless", "runeArmor" ], skill: 5, mounted: false, attacks: 1 },
  { template_key: "rift_knights", kind: "unit", recruit_tier: "elite", faction_slug: "chaos", name: "Рыцари разлома", cost: 13, models: 6, model_health: 1, width: 3, armor_type: "heavy", weapon_type: "puncture", melee: 7, ranged: 0, spell: 0, initiative: 3, abilities: [ "fast", "momentumCharge" ], skill: 5, mounted: false, attacks: 1 },
  # rare
  { template_key: "rift_mutant", kind: "unit", recruit_tier: "rare", faction_slug: "chaos", name: "Мутант разлома", cost: 12, models: 1, model_health: 6, width: 1, armor_type: "magic", weapon_type: "blunt", melee: 5, ranged: 0, spell: 0, initiative: 3, abilities: [ "fear" ], skill: 4, mounted: false, attacks: 2 },
  { template_key: "inferno_cannon", kind: "unit", recruit_tier: "rare", faction_slug: "chaos", name: "Пушка преисподней", cost: 320, models: 1, model_health: 5, width: 2, armor_type: "machine", weapon_type: "demolish", melee: 2, ranged: 8, spell: 0, initiative: 4, abilities: [ "ranged", "machine", "fear", "antiFlying" ], skill: 2, mounted: false, attacks: 1, shooting_template: "line" },
  # heroes
  { template_key: "rift_lord", kind: "hero", recruit_tier: "line", faction_slug: "chaos", name: "Лорд разлома", cost: 12, models: 1, model_health: 4, width: 1, armor_type: "heavy", weapon_type: "slash", melee: 6, ranged: 0, spell: 0, initiative: 5, abilities: [ "leader", "fear" ], skill: 6, mounted: false, attacks: 2 },
  { template_key: "sorcerer", kind: "hero", recruit_tier: "line", faction_slug: "chaos", name: "Чародей Хаоса", cost: 14, models: 1, model_health: 2, width: 1, armor_type: "magic", weapon_type: "magic", melee: 2, ranged: 5, spell: 5, initiative: 5, abilities: [ "wizard" ], skill: 5, mounted: false, attacks: 2 },
  { template_key: "blood_champion", kind: "hero", recruit_tier: "line", faction_slug: "chaos", name: "Чемпион крови", cost: 13, models: 1, model_health: 3, width: 1, armor_type: "heavy", weapon_type: "slash", melee: 6, ranged: 0, spell: 0, initiative: 5, abilities: [ "fearless", "runeArmor" ], skill: 5, mounted: false, attacks: 2 }
]

templates.map! do |attributes|
  attributes = apply_monster_trait!(attributes)
  cost = attributes.fetch(:cost)
  cost = computed_template_cost(attributes) if cost < 50
  attributes.merge(cost: cost)
end

upgrades = [
  # ── Общие ──────────────────────────────────────────────────
  { upgrade_key: "rune_blade", name: "Рунный клинок", category: "weapon", summary: "Melee +2, тип оружия slash.", repeatable: false },
  { upgrade_key: "meteor_hammer", name: "Молот кометы", category: "weapon", summary: "Melee +2, blunt лучше пробивает heavy.", repeatable: false },
  { upgrade_key: "dragonspear", name: "Драконье копье", category: "weapon", summary: "Melee +1, puncture и antiLarge.", repeatable: false },
  { upgrade_key: "gilded_plate", name: "Позолоченный доспех", category: "armor", summary: "Armor heavy и +1 здоровье.", repeatable: false },
  { upgrade_key: "shadow_cloak", name: "Плащ теней", category: "trait", summary: "Получает skirmisher и dodge.", repeatable: false },
  { upgrade_key: "war_banner", name: "Знамя войны", category: "trait", summary: "Если герой в отряде, тот бьет сильнее на фронт.", repeatable: false },
  { upgrade_key: "arcane_focus", name: "Тайный фокус", category: "ability", summary: "Spell power +2.", repeatable: true },
  { upgrade_key: "scaled_hide", name: "Чешуйчатая шкура", category: "armor", summary: "Armor magic и regen.", repeatable: false },
  { upgrade_key: "longbow_mastery", name: "Мастер длинного лука", category: "ability", summary: "Ranged +2 и precision.", repeatable: false },
  { upgrade_key: "veteran_drill", name: "Ветеранская выучка", category: "trait", summary: "Здоровье +1 и melee +1.", repeatable: true },
  { upgrade_key: "battle_prayer", name: "Боевая молитва", category: "ability", summary: "Поддерживаемый отряд получает resolute.", repeatable: false },
  { upgrade_key: "hellfire_breath", name: "Адское дыхание", category: "ability", summary: "Ranged становится breath и +2.", repeatable: false },
  { upgrade_key: "toxin_coating", name: "Токсиновое покрытие", category: "ability", summary: "Первое попадание ослабляет skill и melee цели на 1 до конца боя.", repeatable: false },

  # ── Империя ────────────────────────────────────────────────
  { upgrade_key: "imperial_halberd", faction_slug: "empire", name: "Имперская алебарда", category: "weapon", summary: "Melee +3, puncture и supportRank — удар из второго ряда.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "imperial_drill", faction_slug: "empire", name: "Имперская выучка", category: "trait", summary: "Здоровье +1 и melee +2.", repeatable: true, min_level: 1, general_only: false },
  { upgrade_key: "crown_blessing", faction_slug: "empire", name: "Коронное благословение", category: "ability", summary: "+1 здоровье, resoluteAura и disciplined.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "warhorse", faction_slug: "empire", name: "Боевая лошадь", category: "mount", summary: "Кавалерийская база (MV 7), fast и momentumCharge, +1 melee.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "winged_mount", faction_slug: "empire", name: "Крылатый скакун", category: "mount", summary: "Только генерал, с 3 уровня. Летает (MV 20), monster-база, +1 melee и +1 здоровье, momentumCharge.", repeatable: false, min_level: 3, general_only: true },

  # ── Зеленокожие ────────────────────────────────────────────
  { upgrade_key: "brutal_cleaver", faction_slug: "greenskins", name: "Тяжёлый секач", category: "weapon", summary: "Melee +3 и ferocious.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "mob_drill", faction_slug: "greenskins", name: "Выучка орды", category: "trait", summary: "Здоровье +1 и melee +2.", repeatable: true, min_level: 1, general_only: false },
  { upgrade_key: "mob_rule", faction_slug: "greenskins", name: "Право толпы", category: "trait", summary: "bannerAura и ferocious.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "boar_mount", faction_slug: "greenskins", name: "Боевой кабан", category: "mount", summary: "Кавалерийская база (MV 7), boarCharge, momentumCharge, +1 melee.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "dragon_mount", faction_slug: "greenskins", name: "Дракон-скакун", category: "mount", summary: "Только генерал, с 3 уровня. Летает (MV 20), monster-база, +2 melee, +1 здоровье, fear и ferocious.", repeatable: false, min_level: 3, general_only: true },

  # ── Нежить ─────────────────────────────────────────────────
  { upgrade_key: "grave_blade", faction_slug: "undead", name: "Клинок могил", category: "weapon", summary: "Melee +2 и regen.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "deathly_resilience", faction_slug: "undead", name: "Смертная стойкость", category: "trait", summary: "Здоровье +1, melee +1 и spell +1.", repeatable: true, min_level: 1, general_only: false },
  { upgrade_key: "necromantic_vigor", faction_slug: "undead", name: "Некромантическая сила", category: "ability", summary: "+1 здоровье, regen и fear.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "dread_steed", faction_slug: "undead", name: "Скакун ужаса", category: "mount", summary: "Кавалерийская база (MV 7), fear, momentumCharge, +1 melee.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "giant_bat", faction_slug: "undead", name: "Гигантская летучая мышь", category: "mount", summary: "Только генерал, с 3 уровня. Летает (MV 20), monster-база, +1 melee, +1 здоровье, fear и undead.", repeatable: false, min_level: 3, general_only: true },

  # ── Диколесье ──────────────────────────────────────────────
  { upgrade_key: "heartwood_bow", faction_slug: "wildwood", name: "Лук из сердцевины", category: "weapon", summary: "Ranged +3, precision, forestborn и ranged.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "wild_growth", faction_slug: "wildwood", name: "Дикий рост", category: "trait", summary: "Здоровье +1, melee +1 и ranged +1.", repeatable: true, min_level: 1, general_only: false },
  { upgrade_key: "spirit_bark", faction_slug: "wildwood", name: "Духовная кора", category: "ability", summary: "forestkin и regen.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "forest_stag", faction_slug: "wildwood", name: "Лесной олень", category: "mount", summary: "Кавалерийская база (MV 7), wildborn, fearless, momentumCharge, +2 melee и +1 здоровье.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "sky_hart", faction_slug: "wildwood", name: "Небесный олень", category: "mount", summary: "Только генерал, с 3 уровня. Летает (MV 20), monster-база, +1 melee, +1 здоровье, forestborn и wildborn.", repeatable: false, min_level: 3, general_only: true },

  # ── Хаос ───────────────────────────────────────────────────
  { upgrade_key: "runescarred_blade", faction_slug: "chaos", name: "Рунный клинок Хаоса", category: "weapon", summary: "Melee +3 и runeArmor.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "chaos_mutation", faction_slug: "chaos", name: "Мутация Хаоса", category: "trait", summary: "Здоровье +1 и melee +2.", repeatable: true, min_level: 1, general_only: false },
  { upgrade_key: "dark_gift", faction_slug: "chaos", name: "Тёмный дар", category: "ability", summary: "+1 здоровье, spell +2 и fear.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "chaos_steed", faction_slug: "chaos", name: "Скакун Хаоса", category: "mount", summary: "Кавалерийская база (MV 7), fear, momentumCharge, +1 melee и +1 здоровье.", repeatable: false, min_level: 1, general_only: false },
  { upgrade_key: "demon_form", faction_slug: "chaos", name: "Демонический облик", category: "transform", summary: "Только генерал, с 3 уровня. Летает (MV 20), monster-база, +2 melee, +2 здоровье, +1 spell, fear и momentumCharge.", repeatable: false, min_level: 3, general_only: true }
]

factions.each_with_index do |attributes, index|
  faction = Faction.find_or_initialize_by(slug: attributes.fetch(:slug))
  faction.update!(attributes.merge(position: index))
end

template_keys = templates.map { |entry| entry.fetch(:template_key) }

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

ArmyTemplate.where.not(template_key: template_keys).destroy_all

upgrade_keys = upgrades.map { |entry| entry.fetch(:upgrade_key) }

upgrades.each_with_index do |attributes, index|
  faction = attributes[:faction_slug] ? Faction.find_by!(slug: attributes.delete(:faction_slug)) : nil
  HeroUpgrade.find_or_initialize_by(upgrade_key: attributes.fetch(:upgrade_key)).update!(
    attributes.merge(faction: faction, position: index)
  )
end

HeroUpgrade.where.not(upgrade_key: upgrade_keys).delete_all

abilities.each do |attributes|
  Ability.find_or_initialize_by(key: attributes.fetch(:key)).update!(attributes)
end

ArmyTemplate.find_each do |template|
  template.army_template_abilities.delete_all
  template.abilities.each do |ability_key|
    template.army_template_abilities.create!(ability: Ability.find_by!(key: ability_key))
  end
end

Sim::Catalog::Loader.reset!
CatalogVersion.current!
# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
