module Sim
  module Campaign
    # Roster unlock ladder: spend treasury to raise recruit_access.
    # Level 0 = line only. Heroes/elite/rare are slot caps (hero max 3, rare max 4).
    module RecruitAccess
      module_function

      MAX_LEVEL = 5
      UPGRADE_COST = [ 0, 100, 150, 200, 250, 300 ].freeze

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
