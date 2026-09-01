module Sim
  module Entities
    class Factory
      def initialize(catalog, id_sequence:)
        @catalog = catalog
        @id_sequence = id_sequence
      end

      def sequence_value
        @id_sequence[:value]
      end

      def create_unit(template_id, owner_id)
        template = @catalog.template(template_id)
        raise ArgumentError, "unknown template" unless template && template[:kind] == "unit"

        max_health = template[:models] * template[:model_health]
        entity = base_entity(
          id: next_id("unit"),
          owner_id: owner_id,
          template: template,
          kind: "unit",
          archetype: "formation",
          max_health: max_health,
          current_health: max_health,
          cost: template[:cost],
          spell: 0,
          progression: nil,
          hero: nil,
          state_extra: { attached_hero_ids: [] }
        )
        Footprint.sync_entity!(entity)
      end

      def create_hero(template_id, owner_id, free: false, general: free)
        template = @catalog.template(template_id)
        raise ArgumentError, "unknown template" unless template && template[:kind] == "hero"

        entity = base_entity(
          id: next_id("hero"),
          owner_id: owner_id,
          template: template,
          kind: "hero",
          archetype: "character",
          max_health: template[:model_health],
          current_health: template[:model_health],
          cost: free ? 0 : template[:cost],
          spell: template[:spell],
          progression: {
            level: 1,
            experience: 0,
            spent_experience: 0,
            pending_draft: [],
            picked_upgrade_ids: []
          },
          hero: { mounted: template[:mounted], general: general, transformed: false, mount_id: nil, base_movement: template[:movement] },
          state_extra: { attached_to: nil, attached_slot: nil }
        )
        Footprint.sync_entity!(entity)
      end

      private

      def next_id(prefix)
        @id_sequence[:value] += 1
        "#{prefix}-#{@id_sequence[:value]}"
      end

      def base_entity(id:, owner_id:, template:, kind:, archetype:, max_health:, current_health:, cost:, spell:, progression:, hero:, state_extra:)
        deployment = Geometry::Battlefield.default_deployment("reserve", "center")
        {
          id: id,
          owner_id: owner_id,
          template_id: template[:id],
          name: template[:name],
          kind: kind,
          components: {
            identity: { faction_id: template[:faction_id], archetype: archetype },
            combat: {
              armor_type: template[:armor_type],
              weapon_type: template[:weapon_type],
              melee: template[:melee],
              ranged: template[:ranged],
              spell: spell,
              skill: template[:skill],
              movement: template[:movement],
              morale: template[:morale],
              shooting_range: template[:shooting_range],
              spell_range: template[:spell_range],
              shooting_template: template[:shooting_template],
              spell_template: template[:spell_template],
              requires_line_of_sight: template[:requires_line_of_sight],
              initiative: template[:initiative],
              attacks: template[:attacks],
              missile_attacks: template[:missile_attacks] || 1
            },
            formation: {
              models: template[:models],
              frontage: template[:frontage],
              max_files: @catalog.formation_rules[:max_files],
              files: 0,
              ranks: 0,
              width: 0,
              depth: 0,
              model_class: template[:model_class],
              model_width: template[:model_base_width],
              model_depth: template[:model_base_depth],
              lane: "center",
              row: "reserve",
              x: deployment[:x],
              y: deployment[:y],
              facing: deployment[:facing]
            },
            abilities: template[:abilities].dup,
            health: { model_health: template[:model_health], max: max_health },
            economy: { cost: cost },
            progression: progression,
            hero: hero
          }.compact,
          state: {
            current_health: current_health,
            is_routing: false
          }.merge(state_extra)
        }
      end
    end
  end
end
