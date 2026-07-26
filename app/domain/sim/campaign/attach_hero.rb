module Sim
  module Campaign
    class AttachHero
      def self.call(campaign:, player_id:, hero_id:, unit_id:)
        new(campaign, player_id, hero_id, unit_id).call
      end

      def initialize(campaign, player_id, hero_id, unit_id)
        @campaign = campaign.deep_dup
        @player_id = player_id
        @hero_id = hero_id
        @unit_id = unit_id
      end

      def call
        player = @campaign.find_player(@player_id)
        hero = player&.dig(:roster)&.find { |entry| entry[:id] == @hero_id }
        unit = player&.dig(:roster)&.find { |entry| entry[:id] == @unit_id }
        return Result.failure("entities not found", code: :not_found) unless player && hero && unit
        return Result.failure("invalid attach targets") unless hero[:kind] == "hero" && unit[:kind] == "unit"
        return Result.failure("mounted heroes cannot attach") if hero.dig(:components, :hero, :mounted)

        if hero[:state][:attached_to] == @unit_id
          hero[:state][:attached_to] = nil
          hero[:state][:attached_slot] = nil
          unit[:state][:attached_hero_ids] = Array(unit[:state][:attached_hero_ids]).reject { |id| id == @hero_id }
          return Result.ok(@campaign)
        end

        player[:roster].each do |entry|
          next unless entry[:kind] == "unit"

          entry[:state][:attached_hero_ids] = Array(entry[:state][:attached_hero_ids]).reject { |id| id == @hero_id }
        end

        hero[:state][:attached_to] = @unit_id
        hero[:state][:attached_slot] = pick_slot(player)
        sync_attached_hero_formation!(hero, unit)
        unit[:state][:attached_hero_ids] = (Array(unit[:state][:attached_hero_ids]) + [ @hero_id ]).uniq
        Result.ok(@campaign)
      end

      private

      def pick_slot(player)
        occupied = player[:roster]
          .select { |entry| entry[:kind] == "hero" }
          .reject { |entry| entry[:id] == @hero_id }
          .select { |entry| entry[:state][:attached_to] == @unit_id }
          .map { |entry| entry[:state][:attached_slot] }
          .compact
        Constants::ATTACH_SLOTS.find { |slot| !occupied.include?(slot) } || "rear"
      end

      def sync_attached_hero_formation!(hero, host)
        host_formation = host[:components][:formation]
        hero_formation = hero[:components][:formation]
        %i[lane row x y facing].each { |key| hero_formation[key] = host_formation[key] }
      end
    end
  end
end
