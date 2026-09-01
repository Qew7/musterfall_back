module Balance
  module Synthetic
    module Duel
      BF = Sim::Geometry::Battlefield
      GAP = Sim::Battle::Pathing::CONTACT + 0.25
      STANDOFF_GAP = GAP + 1.0
      MAX_ITERATIONS = 200

      module_function

      def run!(catalog:, config:, rng:)
        iterations = config[:iterations].to_i.clamp(1, MAX_ITERATIONS)
        contact = normalize_contact(config[:contact])
        deploy = normalize_deploy(config[:deploy])
        left_wins = 0
        right_wins = 0
        total_rounds = 0

        iterations.times do
          battle_rng = Sim::Rng::Seeded.new(rng.rand(0x7FFFFFFF))
          left, right = build_players(catalog, config, contact: contact, deploy: deploy)
          first, second = pick_turn_order(left, right, rng: battle_rng, randomize: config[:random_first_turn])
          result = Sim::Battle::Simulator.call(first, second, catalog, rng: battle_rng, terrain: [])
          total_rounds += Sim::Battle::SemanticSnapshot.build(result)[:rounds].to_i
          if result[:winner_id] == left[:id]
            left_wins += 1
          else
            right_wins += 1
          end
        end

        {
          iterations: iterations,
          left_template: config[:left_template].to_s,
          right_template: config[:right_template].to_s,
          contact: contact,
          deploy: deploy,
          left_models: config[:left_models],
          right_models: config[:right_models],
          left_wins: left_wins,
          right_wins: right_wins,
          left_winrate: (left_wins.to_f / iterations).round(4),
          right_winrate: (right_wins.to_f / iterations).round(4),
          avg_rounds: (total_rounds.to_f / iterations).round(2)
        }
      end

      def build_players(catalog, config, contact:, deploy: "melee")
        factory = Sim::Entities::Factory.new(catalog, id_sequence: { value: 0 })
        left_entity = factory.create_unit(config[:left_template], "duel-left")
        right_entity = factory.create_unit(config[:right_template], "duel-right")
        apply_simulation_mutant!(left_entity, config[:left_template])
        apply_simulation_mutant!(right_entity, config[:right_template])
        apply_models!(left_entity, config[:left_models])
        apply_models!(right_entity, config[:right_models])
        deploy!(left_entity, right_entity, contact: contact, deploy: deploy)

        left_template = catalog.template(config[:left_template])
        right_template = catalog.template(config[:right_template])
        [
          player("duel-left", left_template[:faction_id], left_entity),
          player("duel-right", right_template[:faction_id], right_entity)
        ]
      end

      def player(id, faction_id, entity)
        {
          id: id,
          name: id,
          is_bot: true,
          faction_id: faction_id,
          roster: [ entity ]
        }
      end

      def apply_simulation_mutant!(entity, template_id)
        template = { id: template_id.to_s }
        return unless Sim::Campaign::RecruitRules::ChaosSpawn.applies?(template)

        treasury = Sim::Campaign::RecruitRules::ChaosSpawn::SIMULATION_TREASURY
        rng = Sim::Rng::Seeded.new(Zlib.crc32("balance-duel:#{template_id}"))
        Sim::Campaign::RecruitRules::ChaosSpawn.apply!(entity, treasury, rng)
      end

      def apply_models!(entity, count)
        return if count.blank?

        models = count.to_i
        return unless models.positive?

        health = entity.dig(:components, :health, :model_health).to_i
        entity[:components][:formation][:models] = models
        entity[:state][:current_health] = models * health
        entity[:components][:health][:max] = models * health
        Sim::Entities::Footprint.sync_entity!(entity)
      end

      def deploy!(left_entity, right_entity, contact:, deploy: "melee")
        Sim::Entities::Footprint.sync_entity!(left_entity)
        Sim::Entities::Footprint.sync_entity!(right_entity)
        left_dims = footprint_dims(left_entity)
        right_dims = footprint_dims(right_entity)
        gap = engagement_gap(left_entity, right_entity, deploy: deploy)

        left_x = 12.0
        left_y = BF::CONFIG[:height] / 2.0
        place_entity!(left_entity, x: left_x, y: left_y, facing: 0)

        battle_left_x, battle_left_y = left_x, left_y
        right_battle_x, right_battle_y, right_facing = contact_position(
          contact,
          battle_left_x,
          battle_left_y,
          left_dims,
          right_dims,
          gap: gap
        )
        right_local_x = BF::CONFIG[:width] - 1 - right_battle_x
        right_local_y = BF::CONFIG[:height] - 1 - right_battle_y
        right_local_facing = BF.normalize_facing(right_facing + 180)
        place_entity!(right_entity, x: right_local_x, y: right_local_y, facing: right_local_facing)
      end

      def contact_position(contact, left_x, left_y, left_dims, right_dims, gap: GAP)
        case contact
        when "flank"
          [
            left_x + left_dims[:half_depth] + gap + right_dims[:half_depth],
            left_y + left_dims[:half_width] + gap + right_dims[:half_width],
            270.0
          ]
        when "rear"
          [
            left_x - left_dims[:half_depth] - gap - right_dims[:half_depth],
            left_y,
            0.0
          ]
        else
          [
            left_x + left_dims[:half_depth] + gap + right_dims[:half_depth],
            left_y,
            180.0
          ]
        end
      end

      def engagement_gap(left_entity, right_entity, deploy:)
        return GAP if deploy.to_s == "melee"

        ranges = [ shooting_range_for(left_entity), shooting_range_for(right_entity) ].select(&:positive?)
        return STANDOFF_GAP if ranges.empty?

        [ ranges.max, STANDOFF_GAP ].max.to_f
      end

      def pick_turn_order(left, right, rng:, randomize:)
        return [ left, right ] unless randomize
        return [ right, left ] if rng.rand(2).zero?

        [ left, right ]
      end

      def shooting_range_for(entity)
        entity.dig(:components, :combat, :shooting_range).to_i
      end

      def place_entity!(entity, x:, y:, facing:)
        formation = entity[:components][:formation]
        formation[:x] = x
        formation[:y] = y
        formation[:facing] = facing
        formation[:row] = "front"
        formation[:lane] = "center"
        slots = BF.sync_formation_slots_from_deployment(formation)
        formation[:lane] = slots[:lane]
        formation[:row] = slots[:row]
      end

      def footprint_dims(entity)
        formation = entity[:components][:formation]
        {
          half_width: formation[:width].to_f / 2.0,
          half_depth: formation[:depth].to_f / 2.0
        }
      end

      def normalize_contact(value)
        contact = value.to_s.presence || "front"
        return contact if %w[front flank rear].include?(contact)

        "front"
      end

      def normalize_deploy(value)
        deploy = value.to_s.presence || "melee"
        return deploy if %w[melee ranged].include?(deploy)

        "melee"
      end
    end
  end
end
