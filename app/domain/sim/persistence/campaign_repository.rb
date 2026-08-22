module Sim
  module Persistence
    class CampaignRepository
      def load(game)
        players = game.game_players.includes(game_entities: [ :hero_attachment, :unit_attachments ]).order(:position)
        attachments = GameEntityAttachment.where(hero_entity_id: players.flat_map { |player| player.game_entities.map(&:id) })
        attachments_by_hero = attachments.index_by(&:hero_entity_id)
        attachments_by_unit = attachments.group_by(&:unit_entity_id)

        Campaign::State.new(
          round: game.current_round,
          winner_id: game.winner_player_key,
          last_round_report: Campaign::State.deep_symbolize(game.last_round_report),
          version: game.campaign_version,
          id_sequence: players.flat_map { |player| player.game_entities.map { |entity| entity.external_key[/\d+/].to_i } }.max.to_i,
          players: players.map { |player| serialize_player(player, attachments_by_hero, attachments_by_unit) }
        )
      end

      def replace!(game, state)
        GamePlayer.transaction do
          existing_players = game.game_players.includes(:game_entities).index_by(&:external_key)
          keep_player_keys = state.players.map { |player| player[:id] }

          existing_players.each do |key, record|
            record.destroy! unless keep_player_keys.include?(key)
          end

          state.players.each_with_index do |player, index|
            record = existing_players[player[:id]] || game.game_players.build(external_key: player[:id])
            record.assign_attributes(
              name: player[:name],
              is_bot: player[:is_bot],
              status: player[:status],
              faction_key: player[:faction_id],
              treasury: player[:treasury],
              recruit_access: player[:recruit_access].to_i,
              recruit_strategy: player[:recruit_strategy],
              victories: player[:victories],
              position: index,
              round_notes: player[:round_notes] || []
            )
            record.save!

            replace_entities!(record, player[:roster] || [])
          end

          game.update!(
            current_round: state.round,
            winner_player_key: state.winner_id,
            last_round_report: state.last_round_report,
            campaign_version: state.version,
            status: state.winner_id ? "finished" : game.status
          )
        end
      end

      private

      def serialize_player(player, attachments_by_hero, attachments_by_unit)
        entities_by_id = player.game_entities.index_by(&:id)
        {
          id: player.external_key,
          name: player.name,
          is_bot: player.is_bot,
          status: player.status,
          faction_id: player.faction_key,
          treasury: player.treasury,
          recruit_access: player.recruit_access.to_i,
          recruit_strategy: player.recruit_strategy,
          victories: player.victories,
          round_notes: player.round_notes,
          roster: player.game_entities.map do |entity|
            serialize_entity(entity, attachments_by_hero, attachments_by_unit, entities_by_id)
          end
        }
      end

      def serialize_entity(entity, attachments_by_hero, attachments_by_unit, entities_by_id)
        hero_attachment = attachments_by_hero[entity.id]
        unit_attachments = attachments_by_unit[entity.id] || []
        state = {
          current_health: entity.current_health,
          is_routing: entity.is_routing
        }

        if entity.kind == "hero"
          state[:attached_to] = hero_attachment ? entities_by_id[hero_attachment.unit_entity_id]&.external_key : nil
          state[:attached_slot] = hero_attachment&.slot
        else
          state[:attached_hero_ids] = unit_attachments.filter_map { |attachment| entities_by_id[attachment.hero_entity_id]&.external_key }
        end

        {
          id: entity.external_key,
          owner_id: entity.game_player.external_key,
          template_id: entity.template_key,
          name: entity.name,
          kind: entity.kind,
          components: {
            identity: symbolize(entity.identity),
            combat: symbolize(entity.combat),
            formation: symbolize(entity.formation).merge(
              lane: entity.lane_key,
              row: entity.row_key,
              x: entity.x,
              y: entity.y,
              facing: entity.facing
            ),
            abilities: entity.abilities,
            health: symbolize(entity.health),
            economy: symbolize(entity.economy),
            progression: entity.kind == "hero" ? symbolize(entity.progression) : nil,
            hero: entity.kind == "hero" ? symbolize(entity.hero) : nil
          }.compact,
          state: state
        }
      end

      def replace_entities!(player_record, roster)
        existing = player_record.game_entities.includes(:hero_attachment, :unit_attachments).index_by(&:external_key)
        keep_keys = roster.map { |entity| entity[:id] }

        existing.each do |key, record|
          record.destroy! unless keep_keys.include?(key)
        end

        entity_records = {}
        roster.each do |entity|
          record = existing[entity[:id]] || player_record.game_entities.build(external_key: entity[:id])
          formation = entity.dig(:components, :formation) || {}
          record.assign_attributes(
            kind: entity[:kind],
            template_key: entity[:template_id],
            name: entity[:name],
            current_health: entity.dig(:state, :current_health),
            is_routing: entity.dig(:state, :is_routing),
            row_key: formation[:row] || "reserve",
            lane_key: formation[:lane] || "center",
            x: formation[:x] || 0,
            y: formation[:y] || 0,
            facing: formation[:facing] || 0,
            formation: stringify_keys(formation.except(:lane, :row, :x, :y, :facing)),
            combat: stringify_keys(entity.dig(:components, :combat) || {}),
            abilities: entity.dig(:components, :abilities) || [],
            health: stringify_keys(entity.dig(:components, :health) || {}),
            economy: stringify_keys(entity.dig(:components, :economy) || {}),
            progression: stringify_keys(entity.dig(:components, :progression) || {}),
            hero: stringify_keys(entity.dig(:components, :hero) || {}),
            identity: stringify_keys(entity.dig(:components, :identity) || {})
          )
          record.save!
          entity_records[entity[:id]] = [ record, entity ]
        end

        GameEntityAttachment.where(hero_entity_id: entity_records.values.map { |record, _| record.id }).delete_all
        GameEntityAttachment.where(unit_entity_id: entity_records.values.map { |record, _| record.id }).delete_all

        entity_records.each_value do |record, entity|
          next unless entity[:kind] == "hero"

          unit_key = entity.dig(:state, :attached_to)
          next if unit_key.blank?

          unit_record = entity_records.dig(unit_key, 0)
          next unless unit_record

          GameEntityAttachment.create!(
            hero_entity: record,
            unit_entity: unit_record,
            slot: entity.dig(:state, :attached_slot) || "rear"
          )
        end
      end

      def symbolize(hash)
        hash.to_h.transform_keys(&:to_sym)
      end

      def stringify_keys(hash)
        hash.to_h.transform_keys(&:to_s)
      end
    end
  end
end
