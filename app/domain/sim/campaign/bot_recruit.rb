module Sim
  module Campaign
    # Bot shopping for roster access + units/heroes. Strategy picked once per bot.
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
        @campaign = campaign.deep_dup
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

          result = RestoreUnit.call(
            campaign: @campaign,
            catalog: @catalog,
            player_id: player[:id],
            entity_id: entity[:id],
            models: models
          )
          @campaign = result.value if result.ok?
        end
      end

      def missing_models(entity)
        max = entity.dig(:components, :formation, :models).to_i
        current = Entities::Footprint.health_to_models(entity)
        max - current
      end

      def shop!(player)
        24.times do
          player = @campaign.find_player(@player_id)
          break unless player && player[:treasury].positive?

          if should_upgrade?(player) && try_upgrade!(player)
            next
          end

          break unless try_recruit!(player)
        end
      end

      def should_upgrade?(player)
        cost = RecruitAccess.upgrade_cost(player[:recruit_access].to_i)
        return false unless cost

        cfg = strategy(player)
        return false if player[:treasury] < cost + cfg[:upgrade_reserve]

        @rng.rand < cfg[:upgrade_chance]
      end

      def try_upgrade!(player)
        result = UpgradeAccess.call(campaign: @campaign, player_id: player[:id])
        return false unless result.ok?

        @campaign = result.value
        true
      end

      def try_recruit!(player)
        options = recruitable(player)
        return false if options.empty?

        template = weighted_pick(options, strategy(player))
        return false unless template

        school_key = wizard_school(template, player)
        result = Recruit.call(
          campaign: @campaign,
          catalog: @catalog,
          player_id: player[:id],
          template_id: template[:id],
          rng: @rng,
          school_key: school_key
        )
        return false unless result.ok?

        @campaign = result.value
        true
      end

      def recruitable(player)
        units = @catalog.unit_templates(player[:faction_id])
        heroes = @catalog.hero_templates(player[:faction_id])
        (units + heroes).select do |template|
          template[:cost] <= player[:treasury] && RecruitAccess.allowed?(player, @catalog, template)
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
