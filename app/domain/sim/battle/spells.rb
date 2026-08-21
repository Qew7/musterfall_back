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
        fireball: { name: "Огненный шар", description: "Швыряет шар пламени во вражеский отряд." },
        ember_cage: { name: "Клетка углей", description: "Наносит 3 урона вражескому отряду, когда тот движется." },
        fire_line: { name: "Огненная черта", description: "Прорезает огненную линию сквозь строй врага." },
        cinder_shield: { name: "Щит углей", description: "Обжигает на 1 урон врага, попавшего по союзнику в ближнем бою." },
        inferno: { name: "Инферно", description: "Покрывает область яростным огненным штормом." },
        ashen_stride: { name: "Пепельный шаг", description: "Несёт союзный отряд вперёд по следу углей." },
        comet: { name: "Комета", description: "Отмечает точку для отложенного небесного удара." },
        chain_lightning: { name: "Цепная молния", description: "Молния прыгает между соседними врагами." },
        foresight: { name: "Предвидение", description: "Повышает навык союзного отряда на 1." },
        starlight: { name: "Звёздный свет", description: "Повышает мораль союзного отряда на 2." },
        gravity_well: { name: "Колодец тяжести", description: "Создаёт тяжёлую местность и замедляет врагов вокруг точки." },
        solar_flare: { name: "Солнечная вспышка", description: "Ослепляет и опаляет открытый вражеский отряд." },
        regrowth: { name: "Отрастание", description: "Восстанавливает раненых в союзном отряде." },
        thorn_wall: { name: "Стена шипов", description: "Поднимает стену цепких терний." },
        entangling_roots: { name: "Цепкие корни", description: "Приковывает вражеский отряд к земле." },
        oakheart: { name: "Дубовое сердце", description: "Делает плоть союзников твёрдой, как древняя древесина." },
        verdant_path: { name: "Зелёный путь", description: "Открывает быстрый живой путь союзнику." },
        wild_bloom: { name: "Дикий цвет", description: "Наполняет область исцеляющей жизнью." },
        wild_fury: { name: "Дикая ярость", description: "Пробуждает хищную силу в союзном отряде." },
        spectral_flock: { name: "Призрачная стая", description: "Призрачная стая рвёт вражеский отряд." },
        dusk_hide: { name: "Шкура сумерек", description: "Вдвое снижает магический урон по союзному отряду." },
        primal_roar: { name: "Первобытный рёв", description: "Снижает мораль ближайших врагов на 2." },
        horn_spear: { name: "Роговое копьё", description: "Метает пробивающее копьё из твёрдого рога." },
        hunting_pack: { name: "Охотничья стая", description: "Призывает трёх призрачных псов рядом с заклинателем." },
        miasma: { name: "Миазма", description: "Замедляет врага липкой тьмой." },
        void_pit: { name: "Яма пустоты", description: "Разверзает смертельную пустоту под точкой поля." },
        weakening_fog: { name: "Слабящий туман", description: "Лишает удара врагов в области." },
        shadowstep: { name: "Шаг тени", description: "Переносит союзный отряд к флангу ближайшего врага." },
        doppelganger: { name: "Двойник", description: "Создаёт копию союзного отряда на 1d3+1 хода." },
        cloak_of_night: { name: "Плащ ночи", description: "Не позволяет выбирать союзный отряд целью стрельбы." },
        raise_dead: { name: "Поднять мёртвых", description: "Поднимает отряд из пяти мертвецов." },
        soul_drain: { name: "Иссушение души", description: "Вытягивает жизненную силу из врага." },
        grave_dance: { name: "Пляска мертвецов", description: "Гонит союзный отряд вперёд неживой скоростью." },
        withering: { name: "Увядание", description: "Наносит врагу по 2 урона в начале трёх его ходов." },
        deathly_vigor: { name: "Мёртвая бодрость", description: "Наполняет союзников неутомимой силой смерти." },
        grave_call: { name: "Зов могилы", description: "Возвращает павших моделей в неживой отряд." },
        colossal_stomp: { name: "Исполинская стопа", description: "Гигантская стопа топчет вражеский строй." },
        headbutt: { name: "Башка", description: "Крушит вражеского заклинателя сырой силой." },
        charge_frenzy: { name: "Погнали!", description: "Вгоняет союзный отряд в ярость атаки." },
        hurling_hand: { name: "Швыряющая длань", description: "Швыряет союзный отряд через поле боя." },
        twist_luck: { name: "Кривая удача", description: "Выворачивает удачу против врага." },
        horde_surge: { name: "Натиск орды", description: "Толкает ближайших союзников вперёд единой массой." },
        rift_lightning: { name: "Молния разлома", description: "Бьёт врага нестабильной энергией разлома." },
        earth_split: { name: "Раскол земли", description: "Раскалывает землю смертоносной линией." },
        scorch: { name: "Опаление", description: "Выжигает участок земли огнём порчи." },
        killing_frenzy: { name: "Боевое бешенство", description: "Даёт +3 к ближнему бою и +1 к движению, но наносит 1 урон в конце хода." },
        howling_gale: { name: "Вой бури", description: "Вдвое снижает дальний бой и движение летающих врагов." },
        wasting_wind: { name: "Ветер мора", description: "Наносит врагам на линии по 2 урона в начале трёх их ходов." }
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
