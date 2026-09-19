module Balance
  module ArmyStageReport
    module_function

    def build(battles)
      scope = battles.where(source: "synthetic")
      stage = Arel.sql("COALESCE(metrics->>'army_stage', 'legacy')")
      costs = Arel.sql("SUM(COALESCE((metrics->>'left_army_cost')::numeric, 0) + COALESCE((metrics->>'right_army_cost')::numeric, 0))")
      rows = scope.group(stage).pluck(stage, Arel.sql("COUNT(*)"), costs).to_h do |key, count, total|
        [ key, { stage: key, battles: count, mean_army_cost: (total.to_f / (count * 2)).round(1), factions: {} } ]
      end
      %w[left right].each do |side|
        faction = Arel.sql("metrics->>'#{side}_faction'")
        wins = Arel.sql("SUM(CASE WHEN metrics->>'winner_id' = 'sim-#{side}' THEN 1 ELSE 0 END)")
        scope.group(stage, faction).pluck(stage, faction, Arel.sql("COUNT(*)"), wins).each do |key, name, count, won|
          bucket = rows.fetch(key)[:factions][name] ||= { appearances: 0, wins: 0 }
          bucket[:appearances] += count
          bucket[:wins] += won
        end
      end
      rows.values.sort_by { |entry| entry[:stage] }.each do |entry|
        entry[:factions].each_value { |bucket| bucket[:winrate] = (bucket[:wins].to_f / bucket[:appearances]).round(4) }
      end
    end
  end
end
