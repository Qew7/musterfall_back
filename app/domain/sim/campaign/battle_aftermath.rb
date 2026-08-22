module Sim
  module Campaign
    # Apply post-battle roster mutations: casualty rolls + keep survivors for restore.
    module BattleAftermath
      module_function

      UNIT_DEATH_SIDES = 6
      HERO_DEATH_SIDES = 36

      def apply!(campaign:, battles:, rng:)
        Array(battles).each do |battle|
          apply_side!(campaign, battle, :left, rng)
          apply_side!(campaign, battle, :right, rng)
        end
      end

      def apply_side!(campaign, battle, side_key, rng)
        side = battle[side_key] || battle[side_key.to_s]
        return unless side

        player_id = side[:player_id] || side["player_id"]
        player = campaign.find_player(player_id)
        return unless player

        Array(side[:combatants] || side["combatants"]).each do |combatant|
          apply_combatant!(player, combatant, rng)
        end
      end

      def apply_combatant!(player, combatant, rng)
        entity_id = combatant[:entity_id] || combatant["entity_id"]
        entity = player[:roster].find { |entry| entry[:id] == entity_id }
        return unless entity

        if general?(entity)
          revive_general!(entity)
          return
        end

        starting = (combatant[:starting_models] || combatant["starting_models"]).to_i
        remaining = (combatant[:models_remaining] || combatant["models_remaining"]).to_i
        remaining = 0 if (combatant[:current_health] || combatant["current_health"]).to_i <= 0
        lost = [ starting - remaining, 0 ].max

        sides = death_sides(entity)
        permanent = 0
        lost.times { permanent += 1 if (rng.rand(sides) + 1) == 1 }

        health = entity[:components][:health]
        model_health = health[:model_health].to_i
        return if model_health <= 0

        old_permanent = health[:permanent_losses].to_i
        new_permanent = old_permanent + permanent
        template_models = entity[:components][:formation][:models].to_i + old_permanent
        max_models = [ template_models - new_permanent, 0 ].max

        health[:permanent_losses] = new_permanent
        health[:max] = max_models * model_health
        entity[:components][:formation][:models] = max_models

        current_models = [ remaining, max_models ].min
        entity[:state][:current_health] = current_models * model_health
        entity[:state][:is_routing] = false
        Entities::Footprint.sync_entity!(entity)

        player[:roster].delete(entity) if max_models <= 0
      end

      def general?(entity)
        entity[:kind] == "hero" && !!entity.dig(:components, :hero, :general)
      end

      def death_sides(entity)
        entity[:kind] == "hero" ? HERO_DEATH_SIDES : UNIT_DEATH_SIDES
      end

      def revive_general!(entity)
        health = entity[:components][:health]
        max = health[:max].to_i
        entity[:state][:current_health] = max
        entity[:state][:is_routing] = false
        Entities::Footprint.sync_entity!(entity)
      end
    end
  end
end
