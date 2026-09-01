module Sim
  module Battle
    module Spells
      module Contract
        def key = self::KEY
        def name = Spells.card(self::KEY).fetch(:name)
        def description = Spells.card(self::KEY).fetch(:description)
        def casting_value = self::CASTING_VALUE
        def target_type = self::TARGET_TYPE
        def requires_los? = self::REQUIRES_LOS
        # Optional per-spell range; nil falls back to caster[:spell_range].
        def range = const_defined?(:RANGE, false) ? self::RANGE.to_f : nil

        def legal_targets(context)
          targets = context.legal_targets(target_type, requires_los: requires_los?)
          return targets unless const_defined?(:SELECT_TARGETS, false)

          Array(self::SELECT_TARGETS.call(context, targets))
        end

        # Optional per-spell hooks:
        #   SCORE.call(context, target) -> Float            full replace
        #   SCORE_ADJUST.call(context, target, base) -> Float  tweak profile score
        #   SELECT_TARGETS.call(context, targets) -> Array
        def score(context, target)
          if const_defined?(:SCORE, false)
            self::SCORE.call(context, target).to_f
          else
            base = context.score(self::SCORE_PROFILE, target, spell: self)
            const_defined?(:SCORE_ADJUST, false) ? self::SCORE_ADJUST.call(context, target, base).to_f : base
          end
        end

        def resolve!(context, target)
          self::EFFECT.call(context, target)
        end

        # Optional replay shape: TEMPLATE = { shape: "circle"|"line"|"chain"|"aura", radius: ... }
        def visual_template
          const_defined?(:TEMPLATE, false) ? self::TEMPLATE : nil
        end
      end

      module Pyromancy
        Contract = Spells::Contract
      end
      module Celestial
        Contract = Spells::Contract
      end
      module Verdancy
        Contract = Spells::Contract
      end
      module Bestial
        Contract = Spells::Contract
      end
      module Shadow
        Contract = Spells::Contract
      end
      module Necromancy
        Contract = Spells::Contract
      end
      module Warcry
        Contract = Spells::Contract
      end
      module Ruin
        Contract = Spells::Contract
      end

      REGISTRY = {
        pyromancy: -> {
          [ Pyromancy::Fireball, Pyromancy::EmberCage, Pyromancy::FireLine,
            Pyromancy::CinderShield, Pyromancy::Inferno, Pyromancy::AshenStride ]
        },
        celestial: -> {
          [ Celestial::Comet, Celestial::ChainLightning, Celestial::Foresight,
            Celestial::Starlight, Celestial::GravityWell, Celestial::SolarFlare ]
        },
        verdancy: -> {
          [ Verdancy::Regrowth, Verdancy::ThornWall, Verdancy::EntanglingRoots,
            Verdancy::Oakheart, Verdancy::VerdantPath, Verdancy::WildBloom ]
        },
        bestial: -> {
          [ Bestial::WildFury, Bestial::SpectralFlock, Bestial::DuskHide,
            Bestial::PrimalRoar, Bestial::HornSpear, Bestial::HuntingPack ]
        },
        shadow: -> {
          [ Shadow::Miasma, Shadow::VoidPit, Shadow::WeakeningFog,
            Shadow::Shadowstep, Shadow::Doppelganger, Shadow::CloakOfNight ]
        },
        necromancy: -> {
          [ Necromancy::RaiseDead, Necromancy::SoulDrain, Necromancy::GraveDance,
            Necromancy::Withering, Necromancy::DeathlyVigor, Necromancy::GraveCall ]
        },
        warcry: -> {
          [ Warcry::ColossalStomp, Warcry::Headbutt, Warcry::ChargeFrenzy,
            Warcry::HurlingHand, Warcry::TwistLuck, Warcry::HordeSurge ]
        },
        ruin: -> {
          [ Ruin::RiftLightning, Ruin::EarthSplit, Ruin::Scorch,
            Ruin::KillingFrenzy, Ruin::HowlingGale, Ruin::WastingWind ]
        }
      }.freeze

      SCHOOL_METADATA = {
        pyromancy: { name: "Пиромантия", description: "Пламя, разрушение и огненное движение." },
        celestial: { name: "Небосвод", description: "Звёзды, молнии, судьба и тяжесть." },
        verdancy: { name: "Зелень", description: "Рост, исцеление, корни и живой ландшафт." },
        bestial: { name: "Звериная", description: "Хищная сила, звери и первобытная ярость." },
        shadow: { name: "Тень", description: "Мрак, слабость, обман и смещение." },
        necromancy: { name: "Некромантия", description: "Смерть, истощение, воскрешение и могила." },
        warcry: { name: "Боевой клич", description: "Грубая сила, питаемая боевым бешенством." },
        ruin: { name: "Порча", description: "Разлом, чума, мутация и опустошение." }
      }.freeze

      TARGET_LABELS = {
        enemy_unit: "вражеский отряд",
        ally_unit: "союзный отряд",
        enemy_caster: "вражеский заклинатель",
        caster: "заклинатель",
        battlefield_point: "точка поля",
        battlefield: "всё поле боя"
      }.freeze

      # ponytail: RU player copy lives here; English NAME/DESCRIPTION in classes stay as fallback keys.
      CARD_COPY = {
        fireball: { name: "Огненный шар", description: "Наносит 3 урона (огонь) выбранному вражескому отряду." },
        ember_cage: { name: "Клетка углей", description: "На 1 ход: когда цель двигается, она получает 3 урона." },
        fire_line: { name: "Огненная черта", description: "Наносит 2 урона (огонь) всем врагам на линии до цели." },
        cinder_shield: { name: "Щит углей", description: "На 1 ход: враг, попавший по союзнику в ближнем бою, получает 1 урон." },
        inferno: { name: "Инферно", description: "Наносит 4 урона (огонь) врагам в радиусе 4″ от точки." },
        ashen_stride: { name: "Пепельный шаг", description: "Переносит союзный отряд вперёд к ближайшему врагу." },
        comet: { name: "Комета", description: "Отмечает точку. В следующем раунде падает удар радиусом 2.5″ (осадный урон)." },
        chain_lightning: { name: "Цепная молния", description: "Наносит 3 урона (молния) цели и ещё двум ближайшим врагам." },
        foresight: { name: "Предвидение", description: "Союзный отряд: SK +1 на 1 ход." },
        starlight: { name: "Звёздный свет", description: "Союзный отряд: MO +2 на 2 хода." },
        gravity_well: { name: "Колодец тяжести", description: "Точка: трудная местность на 2 хода. Враги в 4″: MV −2 и не могут маршировать, 2 хода." },
        solar_flare: { name: "Солнечная вспышка", description: "Наносит 2 урона цели. SK цели −1 на 1 ход." },
        regrowth: { name: "Отрастание", description: "Восстанавливает 3 здоровья союзному отряду." },
        thorn_wall: { name: "Стена шипов", description: "Ставит непроходимую местность «Стена шипов» на 3 хода." },
        entangling_roots: { name: "Цепкие корни", description: "Цель: MV = 0 и не может маршировать, 1 ход." },
        oakheart: { name: "Дубовое сердце", description: "Союзный отряд: входящий урон через броню ×0.7 на 2 хода." },
        verdant_path: { name: "Зелёный путь", description: "Переносит союзный отряд в более безопасную точку рядом." },
        wild_bloom: { name: "Дикий цвет", description: "Восстанавливает 2 здоровья союзникам в радиусе 4″." },
        wild_fury: { name: "Дикая ярость", description: "Союзный отряд: ML +2 на 1 ход." },
        spectral_flock: { name: "Призрачная стая", description: "Наносит 2 урона выбранному вражескому отряду." },
        dusk_hide: { name: "Шкура сумерек", description: "Союзный отряд: входящий магический урон ×0.5 на 2 хода." },
        primal_roar: { name: "Первобытный рёв", description: "Враги в 4″: MO −2 на 1 ход." },
        horn_spear: { name: "Роговое копьё", description: "Наносит 4 урона (колющее) выбранному вражескому отряду." },
        hunting_pack: { name: "Охотничья стая", description: "Призывает отряд из 3 призрачных псов рядом с целью." },
        miasma: { name: "Миазма", description: "Вражеский отряд: MV −2 на 1 ход." },
        void_pit: { name: "Яма пустоты", description: "Наносит 5 урона врагам в радиусе 4″ от точки." },
        weakening_fog: { name: "Слабящий туман", description: "Враги в радиусе 4″: ML −2 на 2 хода." },
        shadowstep: { name: "Шаг тени", description: "Переносит союзный отряд во фланг ближайшего врага." },
        doppelganger: { name: "Двойник", description: "Создаёт копию союзного отряда на 2–4 хода." },
        cloak_of_night: { name: "Плащ ночи", description: "Союзный отряд нельзя выбрать целью стрельбы, 2 хода." },
        raise_dead: { name: "Поднять мёртвых", description: "Призывает 5 поднятых мертвецов рядом с точкой." },
        soul_drain: { name: "Иссушение души", description: "Наносит 3 урона (смерть) врагу и восстанавливает 2 здоровья заклинателю." },
        grave_dance: { name: "Пляска мертвецов", description: "Сдвигает союзный отряд на 4″ к ближайшему врагу." },
        withering: { name: "Увядание", description: "В начале трёх ходов цели она получает 2 урона." },
        deathly_vigor: { name: "Мёртвая бодрость", description: "Союзный отряд: ML +2 на 2 хода." },
        grave_call: { name: "Зов могилы", description: "Возвращает 3 модели в союзный отряд (лечение на 3× здоровье модели)." },
        colossal_stomp: { name: "Исполинская стопа", description: "Наносит 5 урона врагам в радиусе 4″ от точки." },
        headbutt: { name: "Башка", description: "Наносит 3 урона выбранному вражескому заклинателю." },
        charge_frenzy: { name: "Погнали!", description: "Союзный отряд: ML +2 и MV +1 на 1 ход." },
        hurling_hand: { name: "Швыряющая длань", description: "Переносит союзный отряд агрессивно к врагу." },
        twist_luck: { name: "Кривая удача", description: "Вражеский отряд: SK −2 на 1 ход." },
        horde_surge: { name: "Натиск орды", description: "Союзники в 4″ сдвигаются на 3″ к ближайшему врагу." },
        rift_lightning: { name: "Молния разлома", description: "Наносит 3 урона (хаос) выбранному вражескому отряду." },
        earth_split: { name: "Раскол земли", description: "Наносит 4 урона всем врагам на линии до цели." },
        scorch: { name: "Опаление", description: "Наносит 3 урона (огонь) врагам в радиусе 4″ от точки." },
        killing_frenzy: { name: "Боевое бешенство", description: "Союзный отряд: ML +3 и MV +1 на 2 хода. В конце хода получает 1 урон." },
        howling_gale: { name: "Вой бури", description: "Все враги на 2 хода: шанс попадания стрельбы ×0.5. Летающие ещё и MV ×0.5." },
        wasting_wind: { name: "Ветер мора", description: "Враги на линии: в начале трёх их ходов получают по 2 урона." }
      }.freeze

      FACTION_ACCESS = {
        empire: %i[pyromancy celestial bestial shadow],
        greenskins: %i[warcry bestial pyromancy],
        undead: %i[necromancy shadow ruin],
        wildwood: %i[verdancy bestial celestial shadow],
        chaos: %i[ruin pyromancy shadow bestial]
      }.freeze

      def self.schools_for(faction)
        FACTION_ACCESS.fetch(faction.to_sym, [])
      end

      def self.school(key)
        SCHOOL_METADATA.fetch(key.to_sym)
      end

      def self.spell_keys(school)
        REGISTRY.fetch(school.to_sym).call.map(&:key)
      end

      def self.fetch(key)
        REGISTRY.each_value.flat_map(&:call).find { |spell| spell.key == key.to_sym }
      end

      def self.card(key)
        key = key.to_sym
        return CARD_COPY.fetch(key) if CARD_COPY.key?(key)

        spell = REGISTRY.each_value.flat_map(&:call).find { |entry| entry::KEY == key }
        { name: spell::NAME.to_s, description: spell::DESCRIPTION.to_s }
      end

      def self.target_label(type)
        TARGET_LABELS.fetch(type.to_sym, type.to_s)
      end

      def self.serialize_school(key)
        key = key.to_sym
        meta = school(key).transform_keys(&:to_sym)
        keys = Array(spell_keys(key)).map { |entry| entry.to_s }
        spells = Array(meta[:spells]).presence || keys.filter_map { |spell_key| fetch(spell_key) }
        {
          id: key.to_s,
          name: meta[:name].to_s,
          description: meta[:description].to_s,
          spellKeys: keys,
          spells: spells.map { |entry| serialize_spell(entry, key) }
        }
      end

      def self.serialize_spell(entry, school_key)
        if entry.is_a?(Hash)
          entry = entry.transform_keys(&:to_sym)
          spell = fetch(entry[:key])
          {
            key: entry[:key].to_s,
            name: entry[:name].presence || spell&.name.to_s,
            description: entry[:description].presence || spell&.description.to_s,
            castingValue: entry[:casting_value] || entry[:castingValue] || spell&.casting_value,
            targetType: (entry[:target_type] || entry[:targetType] || spell&.target_type).to_s,
            targetLabel: entry[:target_label] || entry[:targetLabel] || target_label(entry[:target_type] || entry[:targetType] || spell&.target_type || :enemy_unit),
            requiresLos: entry.key?(:requires_los) ? entry[:requires_los] : entry.fetch(:requiresLos, spell&.requires_los?),
            schoolId: school_key.to_s,
            schoolName: school(school_key)[:name]
          }
        else
          {
            key: entry.key.to_s,
            name: entry.name,
            description: entry.description,
            castingValue: entry.casting_value,
            targetType: entry.target_type.to_s,
            targetLabel: target_label(entry.target_type),
            requiresLos: entry.requires_los?,
            schoolId: school_key.to_s,
            schoolName: school(school_key)[:name]
          }
        end
      end
    end
  end
end
