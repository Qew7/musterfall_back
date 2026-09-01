module Sim
  module Campaign
    # Bot shopping for roster access + units/heroes. Strategy picked once per bot.
    # Mutates the passed campaign in place; caller owns any isolation copy.
    class BotRecruit
      STRATEGIES = {
        "horde" => {
          upgrade_reserve: 180,
          upgrade_chance: 0.2,
          prefer: %w[line],
          hero_weight: 0.3,
          elite_weight: 0.6,
          rare_weight: 0.3
        },
        "push_elite" => {
          upgrade_reserve: 40,
          upgrade_chance: 0.9,
          prefer: %w[elite rare],
          hero_weight: 1.2,
          elite_weight: 3.0,
          rare_weight: 2.5
        },
        "balanced" => {
          upgrade_reserve: 100,
          upgrade_chance: 0.5,
          prefer: %w[line elite],
          hero_weight: 1.0,
          elite_weight: 1.5,
          rare_weight: 1.2
        },
        "heroes" => {
          upgrade_reserve: 60,
          upgrade_chance: 0.75,
          prefer: %w[line],
          hero_weight: 4.0,
          elite_weight: 1.0,
          rare_weight: 0.8
        }
      }.freeze

      def self.call(campaign:, catalog:, player_id:, rng:)
        new(campaign, catalog, player_id, rng).call
      end

      def initialize(campaign, catalog, player_id, rng)
        @campaign = campaign
        @catalog = catalog
        @player_id = player_id
        @rng = rng
      end

      def call
        player = @campaign.find_player(@player_id)
        return Result.failure("player not found", code: :not_found) unless player

        ensure_strategy!(player)
        restore!(player)
        shop!(player)
        Result.ok(@campaign)
      end

      private

      def ensure_strategy!(player)
        return if STRATEGIES.key?(player[:recruit_strategy].to_s)

        player[:recruit_strategy] = @rng.pick(STRATEGIES.keys)
      end

      def strategy(player)
        STRATEGIES.fetch(player[:recruit_strategy])
      end

      # Spend on casualties before shopping; order follows strategy tier weights.
      # Leaves upgrade_reserve so the bot can still unlock/recruit after.
      def restore!(player)
        cfg = strategy(player)
        damaged = player[:roster].filter_map do |entity|
          missing = missing_models(entity)
          next if missing <= 0

          template = @catalog.template(entity[:template_id])
          next unless template

          [ entity, template, weight_for(template, cfg) ]
        end
        return if damaged.empty?

        damaged.sort_by! { |_, _, weight| -weight }
        damaged.each do |entity, _template, _weight|
          player = @campaign.find_player(@player_id)
          break unless player

          budget = player[:treasury] - cfg[:upgrade_reserve]
          break if budget <= 0

          missing = missing_models(entity)
          next if missing <= 0

          template = @catalog.template(entity[:template_id])
          next unless template

          models = RecruitAccess.affordable_restore_models(template, budget, missing)
          next if models <= 0

          restore_entity!(player, entity, models)
        end
      end

      def missing_models(entity)
        max = entity.dig(:components, :formation, :models).to_i
        current = Entities::Footprint.health_to_models(entity)
        max - current
      end

      def shop!(player)
        recruitable_options = nil
        24.times do
          player = @campaign.find_player(@player_id)
          break unless player && player[:treasury].positive?

          if should_upgrade?(player) && upgrade_access!(player)
            recruitable_options = nil
            next
          end

          recruitable_options = recruitable(player) if recruitable_options.nil?
          break unless try_recruit!(player, recruitable_options)

          recruitable_options = nil
        end
      end

      def should_upgrade?(player)
        cost = RecruitAccess.upgrade_cost(player[:recruit_access].to_i)
        return false unless cost

        cfg = strategy(player)
        return false if player[:treasury] < cost + cfg[:upgrade_reserve]

        @rng.rand < cfg[:upgrade_chance]
      end

      def try_recruit!(player, options)
        return false if options.empty?

        template = weighted_pick(options, strategy(player))
        return false unless template

        recruit_template!(player, template, school_key: wizard_school(template, player))
      end

      def restore_entity!(player, entity, models)
        template = @catalog.template(entity[:template_id])
        return false unless template

        model_health = entity.dig(:components, :health, :model_health).to_i
        return false if model_health <= 0

        max_models = entity.dig(:components, :formation, :models).to_i
        current_models = Entities::Footprint.health_to_models(entity)
        missing = max_models - current_models
        return false if missing <= 0

        restore_count = [ models.to_i, missing, RecruitAccess.affordable_restore_models(template, player[:treasury], missing) ].min
        return false if restore_count <= 0

        cost = RecruitAccess.model_restore_cost(template, restore_count)
        player[:treasury] -= cost
        entity[:state][:current_health] = (current_models + restore_count) * model_health
        entity[:state][:is_routing] = false
        Entities::Footprint.sync_entity!(entity)
        true
      end

      def upgrade_access!(player)
        cost = RecruitAccess.upgrade_cost(player[:recruit_access].to_i)
        return false unless cost
        return false if player[:treasury] < cost

        player[:treasury] -= cost
        player[:recruit_access] = player[:recruit_access].to_i + 1
        slots = RecruitAccess.slots_for(player[:recruit_access])
        player[:round_notes] = [
          "Доступ найма #{player[:recruit_access]}: герои #{slots[:hero]}, elite #{slots[:elite]}, rare #{slots[:rare]} (−#{cost})"
        ]
        true
      end

      def recruit_template!(player, template, school_key: nil)
        cost = RecruitRules::ChaosSpawn.cost(player, template)
        return false if cost <= 0 || player[:treasury] < cost
        return false unless RecruitAccess.allowed?(player, @catalog, template)

        loadout = MagicLoadout.build(
          template: template,
          faction_id: player[:faction_id],
          school_key: school_key,
          rng: @rng
        )
        return false if loadout.failure?

        factory = Entities::Factory.new(@catalog, id_sequence: { value: @campaign.id_sequence })
        entity =
          if template[:kind] == "hero"
            factory.create_hero(template[:id], player[:id], free: false, general: !roster_has_general?(player))
          else
            factory.create_unit(template[:id], player[:id])
          end
        RecruitRules::ChaosSpawn.apply!(entity, cost, @rng) if RecruitRules::ChaosSpawn.applies?(template)
        entity[:components][:hero]&.merge!(loadout.value)
        @campaign.id_sequence = factory.sequence_value
        player[:treasury] -= cost
        player[:roster] << entity
        true
      end

      def roster_has_general?(player)
        Array(player[:roster]).any? { |entry| entry.dig(:components, :hero, :general) }
      end

      def recruitable(player)
        units = @catalog.unit_templates(player[:faction_id])
        heroes = @catalog.hero_templates(player[:faction_id])
        (units + heroes).select do |template|
          cost = RecruitRules::ChaosSpawn.cost(player, template)
          cost.positive? && cost <= player[:treasury] && RecruitAccess.allowed?(player, @catalog, template)
        end
      end

      def weighted_pick(templates, cfg)
        weights = templates.map { |template| [ template, weight_for(template, cfg) ] }
        total = weights.sum { |_, weight| weight }
        return @rng.pick(templates) if total <= 0

        roll = @rng.rand * total
        weights.each do |template, weight|
          roll -= weight
          return template if roll <= 0
        end
        weights.last.first
      end

      def weight_for(template, cfg)
        key = RecruitAccess.slot_key(template).to_s
        base =
          case key
          when "hero" then cfg[:hero_weight]
          when "elite" then cfg[:elite_weight]
          when "rare" then cfg[:rare_weight]
          else 1.0
          end
        prefer_bonus = cfg[:prefer].include?(template[:recruit_tier].to_s) || (key == "hero" && cfg[:hero_weight] >= 2) ? 1.5 : 1.0
        base * prefer_bonus
      end

      def wizard_school(template, player)
        return nil unless template[:abilities].to_a.include?("wizard")

        @rng.pick(Battle::Spells.schools_for(player[:faction_id]))&.to_s
      end
    end
  end
end
