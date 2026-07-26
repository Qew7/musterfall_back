module Sim
  module Campaign
    class HeroDraft
      def self.prepare(campaign:, catalog:, player_id:, hero_id:, rng:)
        new(campaign, catalog, player_id, hero_id, rng).prepare
      end

      def self.pick(campaign:, player_id:, hero_id:, upgrade_id:)
        new(campaign, nil, player_id, hero_id, nil).pick(upgrade_id)
      end

      def initialize(campaign, catalog, player_id, hero_id, rng)
        @campaign = campaign.deep_dup
        @catalog = catalog
        @player_id = player_id
        @hero_id = hero_id
        @rng = rng
      end

      def prepare
        hero = @campaign.find_entity(@player_id, @hero_id)
        return Result.failure("hero not found", code: :not_found) unless hero && hero[:kind] == "hero"
        return Result.failure("hero is not ready to level") unless Upgrades::Draft.level_ready?(hero)

        hero[:components][:progression][:pending_draft] = Upgrades::Draft.roll(hero, @catalog, @rng)
        Result.ok(@campaign)
      end

      def pick(upgrade_id)
        hero = @campaign.find_entity(@player_id, @hero_id)
        return Result.failure("hero not found", code: :not_found) unless hero && hero[:kind] == "hero"
        return Result.failure("upgrade not in draft") unless Array(hero.dig(:components, :progression, :pending_draft)).include?(upgrade_id)
        return Result.failure("unknown upgrade effect") unless Upgrades::Draft.apply!(hero, upgrade_id)

        Result.ok(@campaign)
      end
    end
  end
end
