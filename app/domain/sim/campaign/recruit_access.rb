module Sim
  module Campaign
    # Roster unlock ladder: spend treasury to raise recruit_access.
    # Level 0 = line only. Heroes/elite/rare are slot caps (hero max 3, rare max 4).
    module RecruitAccess
      module_function

      MAX_LEVEL = 5
      UPGRADE_COST = [ 0, 100, 150, 200, 250, 300 ].freeze
      REFRESH_COST = 50
      OFFER_BASE = 3
      OFFER_CAP = 6
      TIER_WEIGHT = { "line" => 3, "elite" => 2, "rare" => 1 }.freeze

      def slots_for(level)
        level = level.to_i.clamp(0, MAX_LEVEL)
        {
          hero: [ level, 3 ].min,
          elite: level,
          rare: [ [ level - 1, 0 ].max, 4 ].min
        }
      end

      def upgrade_cost(current_level)
        next_level = current_level.to_i + 1
        return nil if next_level > MAX_LEVEL

        UPGRADE_COST[next_level]
      end

      def slot_key(template)
        return :hero if template[:kind] == "hero"

        template[:recruit_tier].to_s.to_sym
      end

      def free_starter?(entity)
        entity[:kind] == "hero" && entity.dig(:components, :economy, :cost).to_i.zero?
      end

      def used_slots(player, catalog)
        counts = { hero: 0, elite: 0, rare: 0 }
        Array(player[:roster]).each do |entity|
          next if free_starter?(entity)

          template = catalog.template(entity[:template_id])
          next unless template

          key = slot_key(template)
          counts[key] += 1 if counts.key?(key)
        end
        counts
      end

      def allowed?(player, catalog, template)
        key = slot_key(template)
        return true if key == :line

        slots = slots_for(player[:recruit_access])
        used_slots(player, catalog)[key].to_i < slots[key].to_i
      end

      def offer_size(level)
        [ OFFER_BASE + level.to_i, OFFER_CAP ].min
      end

      def unlocked_tiers(level)
        slots = slots_for(level)
        tiers = [ "line" ]
        tiers << "elite" if slots[:elite].positive?
        tiers << "rare" if slots[:rare].positive?
        tiers
      end

      # nil = shop not opened (tests, synthetic armies). [] = empty vitrine after buys.
      def on_market?(player, template)
        return true if template[:kind] == "hero"
        return true if player[:market_offer].nil?

        Array(player[:market_offer]).map(&:to_s).include?(template[:id].to_s)
      end

      def take_offer!(player, template)
        return if template[:kind] == "hero"

        player[:free_market_refresh] = true if free_refresh_hire?(template)
        return if player[:market_offer].nil?

        player[:market_offer] = Array(player[:market_offer]).reject { |id| id.to_s == template[:id].to_s }
      end

      def free_refresh_hire?(template)
        template[:id].to_s == "unpaid_company" || Array(template[:abilities]).include?("unpaidTab")
      end

      def hold_on_dismiss!(player, entity)
        player[:hold_market] = true if Array(entity.dig(:components, :abilities)).include?("holdMarket")
      end

      def refresh_cost(player)
        player[:free_market_refresh] ? 0 : REFRESH_COST
      end

      def roll_offer!(player, catalog, rng)
        if player[:hold_market]
          player[:hold_market] = false
          return
        end

        player[:market_offer] = sample_offer(player, catalog, rng)
      end

      def refresh_offer!(player, catalog, rng)
        cost = refresh_cost(player)
        return false if player[:treasury].to_i < cost

        player[:treasury] -= cost
        player[:free_market_refresh] = false
        player[:hold_market] = false
        player[:market_offer] = sample_offer(player, catalog, rng)
        true
      end

      def sample_offer(player, catalog, rng)
        n = offer_size(player[:recruit_access])
        pool = unlocked_unit_pool(player, catalog)
        own, merc = pool.partition { |template| template[:faction_id] == player[:faction_id] }
        picked = pick_weighted(own, (n / 2.0).ceil, rng)
        picked.concat(pick_weighted(merc, n - picked.size, rng))
        leftover = pool - picked
        picked.concat(pick_weighted(leftover, n - picked.size, rng)) if picked.size < n
        ensure_line!(picked, pool)
        picked.map { |template| template[:id] }
      end

      def unlocked_unit_pool(player, catalog)
        tiers = unlocked_tiers(player[:recruit_access])
        catalog.recruitable_unit_templates(player[:faction_id]).select { |template|
          tiers.include?(template[:recruit_tier].to_s)
        }
      end

      def pick_weighted(pool, count, rng)
        remaining = pool.dup
        picked = []
        [ count, remaining.size ].min.times do
          total = remaining.sum { |template| TIER_WEIGHT.fetch(template[:recruit_tier].to_s, 1) }
          roll = rng.rand * total
          chosen = remaining.find { |template|
            roll -= TIER_WEIGHT.fetch(template[:recruit_tier].to_s, 1)
            roll <= 0
          } || remaining.last
          remaining.delete(chosen)
          picked << chosen
        end
        picked
      end

      def ensure_line!(picked, pool)
        return picked if picked.any? { |template| template[:recruit_tier].to_s == "line" }

        line = (pool - picked).find { |template| template[:recruit_tier].to_s == "line" }
        return picked unless line

        index = picked.rindex { |template| template[:recruit_tier].to_s != "line" } || picked.length - 1
        picked[index] = line
        picked
      end

      def model_restore_cost(template, models)
        return 0 if models.to_i <= 0 || template[:models].to_i <= 0

        per_model_cost(template) * models.to_i
      end

      def per_model_cost(template)
        return 0 if template[:models].to_i <= 0

        (template[:cost].to_f / template[:models]).ceil
      end

      # How many models treasury can buy, capped by missing.
      def affordable_restore_models(template, treasury, missing)
        missing = missing.to_i
        return 0 if missing <= 0

        per = per_model_cost(template)
        return missing if per <= 0

        [ missing, treasury.to_i / per ].min
      end
    end
  end
end
