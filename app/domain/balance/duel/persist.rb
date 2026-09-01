module Balance
  module Duel
    module Persist
      module_function

      def call!(result:, config:, catalog_version:)
        BalanceDuelRun.create!(
          catalog_version: catalog_version,
          left_template: result[:left_template].to_s,
          right_template: result[:right_template].to_s,
          contact: result[:contact].to_s,
          iterations: result[:iterations].to_i,
          left_models: config[:left_models],
          right_models: config[:right_models],
          left_wins: result[:left_wins].to_i,
          right_wins: result[:right_wins].to_i,
          left_winrate: result[:left_winrate].to_f,
          right_winrate: result[:right_winrate].to_f,
          avg_rounds: result[:avg_rounds].to_f,
          config: config.deep_stringify_keys
        )
      end
    end
  end
end
