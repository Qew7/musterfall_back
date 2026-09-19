module Sim
  # Relationships describe rules, not factions or template IDs. A provider can
  # support several consumers; extra copies remain possible at a lower weight.
  module ArmyComposition
    module_function

    def profile(entity)
      entity.fetch(:components).fetch(:combat, {}).merge(
        kind: entity[:kind], abilities: Array(entity.dig(:components, :abilities)),
        models: Entities::Footprint.health_to_models(entity)
      )
    end

    def role(attributes)
      return :hero if attributes[:kind] == "hero"

      preferences = Battle::Rules.army_roles(attributes)
      preferred = %i[artillery supply ranged flanker frontline].find { |entry| preferences.include?(entry) }
      return preferred if preferred
      return :ranged if attributes[:ranged].to_i.positive?
      return :flanker if attributes[:movement].to_f >= 6

      :frontline
    end

    def recruit_weight(template, roster:, options:, treasury:)
      profiles = roster.map { |entity| profile(entity) }
      copies = roster.count { |entity| entity[:template_id] == template[:id] }
      weight = 1.0 / (1 + copies * 0.75)
      unit_profiles = profiles.reject { |entry| entry[:kind] == "hero" }
      frontline = unit_profiles.count { |entry| role(entry) == :frontline }
      if role(template) == :frontline
        weight *= 2.5 if frontline < [ (unit_profiles.size * 0.4).ceil, 1 ].max
      elsif role(template) == :hero
        weight *= 0.5 if profiles.count { |entry| entry[:kind] == "hero" } > unit_profiles.size / 2
      elsif frontline.zero? && options.any? { |entry| role(entry) == :frontline }
        weight *= 0.4
      end

      Battle::Rules.army_synergies.each do |link|
        if link.provider?(template)
          users = profiles.select { |entry| link.benefits?(entry, template) }
          sources = profiles.select { |entry| users.any? { |user| link.benefits?(user, entry) } }
          demand = users.sum { |entry| link.demand_for(entry) }
          capacity = sources.sum { |entry| link.capacity_for(entry) }
          weight *= demand > capacity ? 4.0 : 1.0 / (1 + sources.size)
        end
        next unless link.consumer?(template)

        sources = profiles.select { |entry| link.benefits?(template, entry) }
        users = profiles.select { |entry| sources.any? { |source| link.benefits?(entry, source) } }
        spare = sources.sum { |entry| link.capacity_for(entry) } - users.sum { |entry| link.demand_for(entry) }
        if spare >= link.demand_for(template)
          weight *= 2.0
        elsif link.required
          partner = options.select { |entry| link.benefits?(template, entry) }.min_by { |entry| entry[:cost] }
          # Keep enough money for the missing partner; don't plan an unaffordable pair.
          weight *= partner && template[:cost] + partner[:cost] <= treasury ? 1.0 : 0.25
        end
      end
      weight
    end

    def partners(entity, placed)
      own = profile(entity)
      Battle::Rules.army_synergies.flat_map do |link|
        placed.filter_map do |ally|
          other = profile(ally)
          placement = link.placement(own, other) || link.placement(other, own)
          [ ally, *placement ] if placement
        end
      end.uniq
    end
  end
end
