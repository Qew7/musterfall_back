module Balance
  module Record
    module_function

    def from_matchup!(matchup, source: "campaign", catalog_version: nil)
      return unless matchup.completed?
      return if BalanceBattleRollup.exists?(round_matchup_id: matchup.id)

      Persist.call!(
        result: matchup.battle_result,
        attacker: matchup.attacker_player,
        defender: matchup.defender_player,
        catalog_version: catalog_version || CatalogVersion.current!,
        round_matchup_id: matchup.id,
        game_id: matchup.game_id,
        source: source
      )
    end
  end
end
