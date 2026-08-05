require "yaml"

module Sim
  module Battle
    module ScenarioCorpus
      VERSION = 1

      module_function

      def load(path)
        raw =
          if File.extname(path.to_s) == ".json"
            JSON.parse(File.read(path))
          else
            YAML.safe_load(File.read(path), aliases: false)
          end
        Sim::Campaign::State.deep_symbolize(raw)
      end

      def run(entry, catalog: Catalog::Loader.load)
        value = Sim::Campaign::State.deep_symbolize(entry)
        result = Simulator.call(
          value.fetch(:attacker),
          value.fetch(:defender),
          catalog,
          rng: Rng::Seeded.new(value.fetch(:seed)),
          map_seed: value.fetch(:map_seed)
        )
        {
          result: result,
          semantic: SemanticSnapshot.build(result),
          expected: value[:expected]
        }
      end

      def export(matchup)
        map_seed = TerrainMap.map_seed(
          rng_seed: matchup.game.rng_seed,
          round: matchup.campaign_round
        )
        current_result = Simulator.call(
          matchup.attacker_player,
          matchup.defender_player,
          Catalog::Loader.load,
          rng: Rng::Seeded.new(matchup.seed),
          map_seed: map_seed
        )
        {
          version: VERSION,
          id: "matchup-#{matchup.id}",
          source: {
            matchup_id: matchup.id,
            game_id: matchup.game_id,
            campaign_round: matchup.campaign_round
          },
          seed: matchup.seed,
          map_seed: map_seed,
          tags: infer_tags(current_result),
          attacker: matchup.attacker_player,
          defender: matchup.defender_player,
          expected: SemanticSnapshot.build(current_result)
        }
      end

      def infer_tags(report)
        actions = SemanticSnapshot.extract_actions(
          Sim::Campaign::State.deep_symbolize(report || {})
        )
        tags = actions.map { |action| action[:type].to_s }.reject(&:empty?).uniq.sort
        tags << "movement" if actions.any? { |action| action[:maneuver] }
        tags.uniq
      end
    end
  end
end
