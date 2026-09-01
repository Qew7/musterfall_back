module Sim
  module Campaign
    module RecruitRules
      module ChaosSpawn
        TEMPLATE_ID = "rift_mutant"
        SIMULATION_TREASURY = 600
        CAPS = { health: 12, melee: 8, skill: 6, attacks: 4, movement: 8 }.freeze
        ABILITIES = %w[flying regen charge armorPiercing antiLarge dodge].freeze

        module_function

        def applies?(template)
          template[:id].to_s == TEMPLATE_ID
        end

        def cost(player, template)
          applies?(template) ? player[:treasury].to_i : template[:cost].to_i
        end

        def apply!(entity, treasury, rng)
          counts = Hash.new(0)
          abilities_added = 0
          mutation_count(treasury).times do
            choices = stat_choices(entity, counts)
            remaining_abilities = ABILITIES - Array(entity.dig(:components, :abilities))
            choices.concat([ :ability ]) if abilities_added < 2 && remaining_abilities.any?
            choice = rng.pick(choices)
            break unless choice

            if choice == :ability
              ability = rng.pick(remaining_abilities)
              entity[:components][:abilities] << ability
              entity[:components][:combat][:movement] = [ entity.dig(:components, :combat, :movement).to_i, 6 ].max if ability == "flying"
              abilities_added += 1
            else
              improve_stat!(entity, choice)
              counts[choice] += 1
            end
          end
          entity[:components][:economy][:cost] = treasury.to_i
          Sim::Entities::Footprint.sync_entity!(entity)
          entity
        end

        def mutation_count(treasury)
          return 0 if treasury.to_i <= 0

          (treasury.to_f / 200.0).ceil
        end

        def stat_choices(entity, counts)
          CAPS.flat_map do |stat, cap|
            next [] if stat_value(entity, stat) >= cap

            Array.new([ 4 - counts[stat], 1 ].max, stat)
          end
        end
        private_class_method :stat_choices

        def stat_value(entity, stat)
          return entity.dig(:components, :health, :max).to_i if stat == :health

          entity.dig(:components, :combat, stat).to_i
        end
        private_class_method :stat_value

        def improve_stat!(entity, stat)
          if stat == :health
            amount = [ 2, CAPS[:health] - entity.dig(:components, :health, :max).to_i ].min
            entity[:components][:health][:max] += amount
            entity[:components][:health][:model_health] += amount
            entity[:state][:current_health] += amount
          else
            entity[:components][:combat][stat] += 1
          end
        end
        private_class_method :improve_stat!
      end
    end
  end
end
